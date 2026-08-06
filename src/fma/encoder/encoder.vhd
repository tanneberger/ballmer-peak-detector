library ieee;
library work;

use ieee.STD_LOGIC_1164.ALL;
use ieee.NUMERIC_STD.ALL;
use ieee.math_real.all;

-- for or_reduce
--use ieee.std_logic_misc.all;
use work.utility_pkg.all;

entity encoder is
    generic(
        G_N  : integer := 8;
        G_ES : integer := 2;
        G_Bs : integer
    );
    port(
        --i_clk       : in  std_logic;
        --i_enable    : in  std_logic;
        i_is_nar      : in  std_logic;
        i_sticky_op1  : in  std_logic;
        i_sign_op1    : in  std_logic;
        i_mant_op1    : in  std_logic_vector((2 * (G_N - G_ES - 3 + 1)) + 2 downto 0);
        i_eff_exp_op1 : in  std_logic_vector(G_Bs + G_ES downto 0);
        o_result      : out std_logic_vector(7 downto 0)
    );
end encoder;

architecture Behavioral of encoder is
    -- constant G_Bs                       : integer := clog2(G_N);
    -- max number of regime bits 
    constant C_MAX_MANTISSA_WIDTH      : integer := G_N - G_ES - 3; -- 2 bit regime + 1 bit sign
    constant C_INTERNAL_MANTISSA_WIDTH : integer := C_MAX_MANTISSA_WIDTH + 3; -- mantissa + hidden, guard, rounding (and sticky) bit 

    -- C_MAX_MANTISSA_WIDTH + Hidden bit + Guard bit + one extra for adjusting/nromalization
    -- constant C_TRUNCATED_MANTISSA_WIDTH : integer := C_MAX_MANTISSA_WIDTH + 4;

    --constant C_INTERNAL_MANTISSA_WIDTH : integer := C_MAX_MANTISSA_WIDTH + 3; -- mantissa + hidden, guard, rounding (and sticky) bit

    signal s_mantissa_overflow    : std_logic;
    signal s_normalized_lod_k     : std_logic_vector(integer(ceil(log2(real(C_INTERNAL_MANTISSA_WIDTH)))) - 1 downto 0);
    signal s_valid_adjusted_lod_k : std_logic_vector(integer(ceil(log2(real(C_INTERNAL_MANTISSA_WIDTH)))) - 1 downto 0);

    signal s_normalized_hidden_mantissa : std_logic_vector(C_INTERNAL_MANTISSA_WIDTH - 1 downto 0);
    signal s_shift_right_sticky         : std_logic;
    signal s_extended_mantissa_overflow : std_logic_vector(G_Bs + G_ES + 1 downto 0);
    signal s_efficient_exponent         : std_logic_vector(G_Bs + G_ES + 1 downto 0);

    signal s_regime_bit : std_logic;
    signal s_shift_tmp  : std_logic;

    signal s_mantissa_length_correct     : std_logic_vector(C_INTERNAL_MANTISSA_WIDTH downto 0);
    signal s_sticky_default              : std_logic;
    -- Encode Posit
    -- could be one bit smaller? no more sign
    -- constant C_EFFICIENT_EXPONENT_WIDHT    : integer := G_Bs + G_ES + 1;
    signal s_adjusted_efficient_exponent : std_logic_vector(G_Bs + G_ES downto 0);

    signal s_abs_efficient_exponent : std_logic_vector(G_Bs + G_ES downto 0); -- abs reduces on bit msb

    signal s_exponent : std_logic_vector(G_ES - 1 downto 0);

    signal s_combined_exp_mantissa : std_logic_vector(G_ES + C_INTERNAL_MANTISSA_WIDTH - 2 downto 0);
    signal s_intermediate          : std_logic_vector(s_combined_exp_mantissa'length downto 0); -- equal to the combined length + 1 from regime stop bit
    signal s_intermediate_tmp      : std_logic_vector(s_combined_exp_mantissa'length - 1 downto 0);
    signal s_sticky_shifted        : std_logic_vector(s_intermediate'length - 1 downto 0); -- intermediate length + 1 bit for sticky
    signal s_sticky_shifted2       : std_logic_vector(s_intermediate'length downto 0); -- intermediate length + 1 bit for sticky

    signal s_drs : std_logic_vector(integer(ceil(log2(real(s_intermediate'length)))) - 1 downto 0);

    -- rounding stuff
    signal s_lsb_bit    : std_logic;
    signal s_guard_bit  : std_logic;
    signal s_sticky_bit : std_logic;

    signal s_round   : std_logic;
    signal s_rounded : std_logic_vector(G_N - 2 downto 0); -- rounded result without sign
    signal s_negated : std_logic_vector(G_N - 2 downto 0); -- 

begin

    s_mantissa_length_correct <= i_mant_op1(i_mant_op1'high downto i_mant_op1'high - C_INTERNAL_MANTISSA_WIDTH);
    s_sticky_default          <= or_reduce(i_mant_op1(C_INTERNAL_MANTISSA_WIDTH - 1 downto 0));

    s_adjusted_efficient_exponent <= i_eff_exp_op1;

    s_mantissa_overflow <= s_mantissa_length_correct(C_INTERNAL_MANTISSA_WIDTH);

    inst_normalisation_LOD : entity work.LOD_T
        generic map(
            G_DATA_WIDTH => C_INTERNAL_MANTISSA_WIDTH
        )
        port map(
            i_x   => s_mantissa_length_correct(C_INTERNAL_MANTISSA_WIDTH - 1 downto 0),
            o_K   => s_normalized_lod_k,
            o_vld => open
        );

    s_valid_adjusted_lod_k <= s_normalized_lod_k when s_mantissa_overflow = '0' else (others => '0');

    -- shift rigth if overflow, because there is a one to the left, else shift left
    -- Shift Mantissa to Normalize
    overflow_shift : process(s_mantissa_length_correct(C_INTERNAL_MANTISSA_WIDTH - 1 downto 0), s_mantissa_overflow, s_valid_adjusted_lod_k) is
    begin
        if s_mantissa_overflow = '1' then
            s_normalized_hidden_mantissa <= '1' & s_mantissa_length_correct(C_INTERNAL_MANTISSA_WIDTH - 1 downto 0)(s_mantissa_length_correct(C_INTERNAL_MANTISSA_WIDTH - 1 downto 0)'high downto 1);
            s_shift_right_sticky         <= s_mantissa_length_correct(C_INTERNAL_MANTISSA_WIDTH - 1 downto 0)(0);
        else
            s_normalized_hidden_mantissa <= std_logic_vector(shift_left(unsigned(s_mantissa_length_correct(C_INTERNAL_MANTISSA_WIDTH - 1 downto 0)), to_integer(unsigned(s_valid_adjusted_lod_k))));
            s_shift_right_sticky         <= '0';
        end if;
    end process overflow_shift;

    s_extended_mantissa_overflow <= (0 => s_mantissa_overflow, others => '0');

    -- Substract Mantissa Shift amount and add Overflow Bit
    process(s_adjusted_efficient_exponent, s_extended_mantissa_overflow, s_valid_adjusted_lod_k)
    begin
        -- unsigned addition before
        s_efficient_exponent <= std_logic_vector(signed(s_adjusted_efficient_exponent) - signed(std_logic_vector(resize(unsigned(s_valid_adjusted_lod_k), G_Bs + G_ES + 2))) + signed(s_extended_mantissa_overflow));
    end process;

    -- Calculate absolute value of efficient exponent to get regime length if overflow occured: 2s complement
    s_abs_efficient_exponent <= std_logic_vector(unsigned(not s_efficient_exponent(G_Bs + G_ES downto 0)) + 1) when s_efficient_exponent(G_Bs + G_ES + 1) = '1' else s_efficient_exponent(G_Bs + G_ES downto 0);

    -- Extract exponent bits
    s_exponent <= s_efficient_exponent(G_ES - 1 downto 0) when s_efficient_exponent(G_Bs + G_ES + 1) = '1' and or_reduce(s_abs_efficient_exponent(G_ES - 1 downto 0)) = '1' else s_abs_efficient_exponent(G_ES - 1 downto 0);

    -- Concatinate Exponent and Mantissa
    s_combined_exp_mantissa <= s_exponent & s_normalized_hidden_mantissa(C_INTERNAL_MANTISSA_WIDTH - 2 downto 0);

    -- Create regime bits for maximum length
    s_regime_bit <= not s_efficient_exponent(G_Bs + G_ES + 1);

    -- Combine Components 
    s_intermediate <= (0 => s_efficient_exponent(G_Bs + G_ES + 1)) & s_combined_exp_mantissa;

    -- Length calculation and correct value of k calculation according to standard
    process(s_efficient_exponent)
    begin
        -- regime positive => 1 bits, and + 1 to compensate -1 from decode step
        if signed(s_efficient_exponent(G_Bs + G_ES + 1 downto G_ES)) >= 0 then
            s_drs <= std_logic_vector(resize(unsigned(s_efficient_exponent(G_Bs + G_ES + 1 downto G_ES)), integer(clog2(s_intermediate'length)))); -- k '1's + '0'
        else
            s_drs <= std_logic_vector(resize(unsigned((not s_efficient_exponent(G_Bs + G_ES + 1 downto G_ES))), integer(clog2(s_intermediate'length)))); -- |k| '0's + '1'
        end if;
    end process;

    -- Idea here: s_drs seems to always be at least one, so shift more efficiently by one, then have a smaller shifter, and no adder needed in s_drs calculation -> in bigger bitranges worth it 
    s_shift_tmp        <= s_intermediate(0);
    s_intermediate_tmp <= s_intermediate(s_intermediate'high downto 1);

    inst_sticky_shifter_decide : entity work.sticky_shift_det(Tree)
        generic map(
            C_DATA_WIDTH => s_intermediate'length - 1
        )
        port map(
            i_number      => s_intermediate_tmp,
            i_shift_count => s_drs,
            i_shift_bit   => s_regime_bit,
            o_result      => s_sticky_shifted
        );

    -- Calculate Bits for rounding, added sticky from big rounder
    s_sticky_bit <= s_sticky_shifted(0) or i_sticky_op1 or s_shift_right_sticky or s_shift_tmp or s_sticky_default;
    s_guard_bit  <= s_sticky_shifted(1);
    s_lsb_bit    <= s_sticky_shifted(2);

    -- Check if result needs to be rounded
    s_round <= (s_guard_bit and (s_lsb_bit or s_sticky_bit));

    s_sticky_shifted2 <= s_regime_bit & s_sticky_shifted;

    process(s_sticky_shifted2, s_round)
        -- variable v_round           : std_logic_vector(C_INTERMEDIATE_WIDTH downto 0);
        variable v_round           : std_logic_vector(G_N - 2 downto 0);
        -- variable v_appended_sticky : std_logic_vector(C_INTERMEDIATE_WIDTH downto 0);
        variable v_appended_sticky : std_logic_vector(G_N - 2 downto 0);

    begin
        v_appended_sticky := s_sticky_shifted2(G_N downto 2);

        if s_round = '1' then
            v_round := std_logic_vector(unsigned(v_appended_sticky) + 1);
        else
            v_round := v_appended_sticky;
        end if;
        s_rounded <= v_round;
    end process;

    -- Apply Sign
    s_negated <= (std_logic_vector(unsigned(not s_rounded) + 1)) when i_sticky_op1 = '1' else s_rounded;

    -- Apply Special Result Values
    -- o_result <= i_is_nar & (G_N - 2 downto 0 => '0') when (i_is_nar = '1' or r2_is_zero = '1') or (s_normalized_hidden_mantissa(C_INTERNAL_MANTISSA_WIDTH - 1) = '0' and s_mantissa_overflow = '0') else i_sign_op1 & s_negated;
    o_result <= i_is_nar & (G_N - 2 downto 0 => '0') when (i_is_nar = '1') or (s_normalized_hidden_mantissa(C_INTERNAL_MANTISSA_WIDTH - 1) = '0' and s_mantissa_overflow = '0') else i_sign_op1 & s_negated;

end Behavioral;
