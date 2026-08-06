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
        i_mant_op1   : in  std_logic_vector((2 * (G_N - G_ES - 3 + 1)) - 1 downto 0);
        i_eff_exp_op1 : in  std_logic_vector(G_Bs + G_ES downto 0);

        -- input operand 2
        i_mant_op2   : in  std_logic_vector((2 * (G_N - G_ES - 3 + 1)) - 1 downto 0);
        i_eff_exp_op2 : in  std_logic_vector(G_Bs + G_ES downto 0);

        -- outputs
        o_sticky             : out std_logic;
        o_mant_result    : out std_logic_vector((2 * (G_N - G_ES - 3 + 1)) - 1 downto 0);
        o_eff_exp_add_result : out std_logic_vector(G_Bs + G_ES downto 0)
    );
end entity adder;

architecture Behavioral of adder is
    -- constant
    constant C_INTERNAL_MANTISSA_WIDTH : integer := (2 * (G_N - G_ES - 3 + 1));
    -- signals
    signal   s_op_mul_greater_op_add : std_logic;

    signal s_larger_eff_exp, s_smaller_eff_exp : std_logic_vector(G_Bs + G_ES downto 0);
    signal s_larger_mant, s_smaller_mant : std_logic_vector(i_mant_op1'range);
    signal s_efficient_exponent_difference : std_logic_vector(G_Bs + G_ES downto 0);
    signal s_shift_out_of_range : std_logic;
    signal s_saturated_shift_count : std_logic_vector(G_Bs - 1 downto 0);

begin

    -- TODO greater than more area efficient by first comparing exponet then mantissa but mor mux
    -- '1' when multiplication operator result bigger then operand c
    s_op_mul_greater_op_add <= '1' when unsigned(i_eff_exp_op1 & i_mant_op1) > unsigned(i_eff_exp_op2 & i_mant_op2) else '0'; 

    s_larger_eff_exp <= i_eff_exp_op1 when s_op_mul_greater_op_add = '1' else i_eff_exp_op2;
    s_smaller_eff_exp <= i_eff_exp_op1 when s_op_mul_greater_op_add = '0' else i_eff_exp_op2;

    s_larger_mant <= i_mant_op1 when s_op_mul_greater_op_add = '1' else i_mant_op2;
    s_smaller_mant <= i_mant_op1 when s_op_mul_greater_op_add = '0' else i_mant_op2;

    s_efficient_exponent_difference <= std_logic_vector(signed(s_larger_eff_exp) - signed(s_smaller_eff_exp));
    s_shift_out_of_range <= '1' when unsigned(s_efficient_exponent_difference) >= C_INTERNAL_MANTISSA_WIDTH else '0';

    s_saturated_shift_count <= s_efficient_exponent_difference(G_Bs - 1 downto 0) when s_shift_out_of_range = '0' else (others => '1'); -- Shift all bits out

inst_align_sticky_shift : entity work.sticky_shift_det
        generic map(
            C_DATA_WIDTH => C_INTERNAL_MANTISSA_WIDTH+2
        )
        port map(
            i_number      => s_smaller_mant & (1 downto 0 => '0'),
            i_shift_count => s_saturated_shift_count, --s_efficient_exponent_difference(C_Bs-1 downto 0),
            o_result      => s_aligned_mantissa
        );

end architecture Behavioral;
