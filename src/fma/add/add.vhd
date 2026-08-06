library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity adder is
    generic(
        G_N  : integer := 8;
        G_ES : integer := 2;
        G_Bs : integer
    );
    port(
        -- input operand 1
        i_sign_op1           : in  std_logic;
        i_mant_op1           : in  std_logic_vector((2 * (G_N - G_ES - 3 + 1)) - 1 downto 0);
        i_eff_exp_op1        : in  std_logic_vector(G_Bs + G_ES downto 0);
        -- input operand 2
        i_sign_op2           : in  std_logic;
        i_mant_op2           : in  std_logic_vector((2 * (G_N - G_ES - 3 + 1)) - 1 downto 0);
        i_eff_exp_op2        : in  std_logic_vector(G_Bs + G_ES downto 0);
        -- outputs
        o_sign_result        : out std_logic;
        o_sticky_result      : out std_logic;
        o_mant_result        : out std_logic_vector((2 * (G_N - G_ES - 3 + 1)) +2 downto 0);
        o_eff_exp_add_result : out std_logic_vector(G_Bs + G_ES downto 0)
    );
end entity adder;

architecture Behavioral of adder is
    -- constant
    constant C_INTERNAL_MANTISSA_WIDTH : integer := (2 * (G_N - G_ES - 3 + 1));
    -- signals
    signal   s_op_mul_greater_op_add   : std_logic;
    signal s_operation : std_logic;

    signal s_larger_eff_exp, s_smaller_eff_exp : std_logic_vector(G_Bs + G_ES downto 0);
    signal s_larger_mant, s_smaller_mant       : std_logic_vector(i_mant_op1'range);
    signal s_efficient_exponent_difference     : std_logic_vector(G_Bs + G_ES downto 0);
    signal s_shift_out_of_range                : std_logic;
    signal s_saturated_shift_count             : std_logic_vector(G_Bs - 1 downto 0);

    signal s_aligned_mantissa_padded : std_logic_vector(C_INTERNAL_MANTISSA_WIDTH + 2 downto 0);
    signal s_aligned_mantissa : std_logic_vector(C_INTERNAL_MANTISSA_WIDTH + 2 -1 downto 0);
    signal s_alignment_sticky : std_logic;

    signal s_larger_hidden_mantissa_padded : std_logic_vector(C_INTERNAL_MANTISSA_WIDTH-1 +2 downto 0);
    signal s_signed_aligned_hidden_mantissa : std_logic_vector(C_INTERNAL_MANTISSA_WIDTH+2 downto 0);
    signal s_summed_mantissa : std_logic_vector(C_INTERNAL_MANTISSA_WIDTH+2  downto 0);
begin

    -- TODO greater than more area efficient by first comparing exponet then mantissa but mor mux
    -- '1' when multiplication operator result bigger then operand c
    s_op_mul_greater_op_add <= '1' when unsigned(i_eff_exp_op1 & i_mant_op1) > unsigned(i_eff_exp_op2 & i_mant_op2) else '0';
    s_operation <= i_sign_op1 xnor i_sign_op2;


    s_larger_eff_exp  <= i_eff_exp_op1 when s_op_mul_greater_op_add = '1' else i_eff_exp_op2;
    s_smaller_eff_exp <= i_eff_exp_op1 when s_op_mul_greater_op_add = '0' else i_eff_exp_op2;

    s_larger_mant  <= i_mant_op1 when s_op_mul_greater_op_add = '1' else i_mant_op2;
    s_smaller_mant <= i_mant_op1 when s_op_mul_greater_op_add = '0' else i_mant_op2;

    s_efficient_exponent_difference <= std_logic_vector(signed(s_larger_eff_exp) - signed(s_smaller_eff_exp));
    s_shift_out_of_range            <= '1' when unsigned(s_efficient_exponent_difference) >= C_INTERNAL_MANTISSA_WIDTH else '0';

    s_saturated_shift_count <= s_efficient_exponent_difference(G_Bs - 1 downto 0) when s_shift_out_of_range = '0' else (others => '1'); -- Shift all bits out

    inst_align_sticky_shift : entity work.sticky_shift_det
        generic map(
            C_DATA_WIDTH => C_INTERNAL_MANTISSA_WIDTH + 2
        )
        port map(
            i_number      => s_smaller_mant & (1 downto 0 => '0'),
            i_shift_bit   => '0',
            i_shift_count => s_saturated_shift_count, --s_efficient_exponent_difference(C_Bs-1 downto 0),
            o_result      => s_aligned_mantissa_padded
        );

    s_alignment_sticky <= s_aligned_mantissa_padded(0) or s_shift_out_of_range; --or_reduce(s_efficient_exponent_difference(C_Bs+G_ES downto C_Bs));
    s_aligned_mantissa <= s_aligned_mantissa_padded(C_INTERNAL_MANTISSA_WIDTH + 2 downto 1);

    s_larger_hidden_mantissa_padded <= s_larger_mant & (1 downto 0 => '0');

    -- error correction in case of subtraction
    process(s_operation, s_aligned_mantissa, s_alignment_sticky)
    begin
        if s_operation = '0' then
            -- SUBTRAKTION
            if s_alignment_sticky = '1' then
                s_signed_aligned_hidden_mantissa <= std_logic_vector(unsigned(not ("0" & s_aligned_mantissa(C_INTERNAL_MANTISSA_WIDTH + 1 downto 0))));
            else
                s_signed_aligned_hidden_mantissa <= std_logic_vector(unsigned(not ("0" & s_aligned_mantissa(C_INTERNAL_MANTISSA_WIDTH + 1 downto 0))) + 1);
            end if;
        else
            s_signed_aligned_hidden_mantissa <= "0" & s_aligned_mantissa(C_INTERNAL_MANTISSA_WIDTH +1 downto 0);
        end if;
    end process;

    s_summed_mantissa <= std_logic_vector(signed(s_larger_hidden_mantissa_padded) + signed(s_signed_aligned_hidden_mantissa));

    o_sticky_result <= s_alignment_sticky;
    o_sign_result <= i_sign_op1 when s_op_mul_greater_op_add = '1' else i_sign_op2;
    o_mant_result <= s_summed_mantissa;
    o_eff_exp_add_result <= s_larger_eff_exp;
end architecture Behavioral;
