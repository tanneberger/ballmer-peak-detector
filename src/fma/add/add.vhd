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
    -- signals
    signal   s_op_mul_greater_op_add : std_logic;

    signal s_larger_eff_exp, s_smaller_eff_exp : std_logic_vector(G_Bs + G_ES + 1 downto 0);
    signal s_larger_mant, s_smaller_mant : std_logic_vector(i_mant_product_mul'range)
begin

    -- TODO greater than more area efficient by first comparing exponet then mantissa but mor mux
    -- '1' when multiplication operator result bigger then operand c
    s_op_mul_greater_op_add <= '1' when unsigned(i_eff_exp_mul & i_mant_product_mul) > unsigned(i_eff_exp_c & i_mant_c) else '0'; 

    s_larger_eff_exp <= i_eff_exp_mul when s_op_mul_greater_op_add = '1' else i_eff_exp_c;
end architecture Behavioral;
