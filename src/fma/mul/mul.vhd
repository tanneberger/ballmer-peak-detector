library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity multiplier is
    generic(
        G_N  : integer := 8;
        G_ES : integer := 2;
        G_Bs : integer
    );
    port(
        -- input operand 1
        i_sign_op1       : in  std_logic;
        i_mant_op1       : in  std_logic_vector((2 * (G_N - G_ES - 3 + 1)) - 1 downto 0);
        i_eff_exp_op1    : in  std_logic_vector(G_Bs + G_ES downto 0);
        -- input operand 2
        i_sign_op2       : in  std_logic;
        i_mant_op2       : in  std_logic_vector((2 * (G_N - G_ES - 3 + 1)) - 1 downto 0);
        i_eff_exp_op2    : in  std_logic_vector(G_Bs + G_ES downto 0);
        -- output
        o_sign_result    : out std_logic;
        o_mant_result    : out std_logic_vector((2 * (G_N - G_ES - 3 + 1)) - 1 downto 0);
        o_eff_exp_result : out std_logic_vector(G_Bs + G_ES downto 0);
    );
end entity multiplier;

architecture Behavioral of multiplier is
    -- constant
    constant C_MAX_MANTISSA_WIDTH : integer := G_N - G_ES - 3; -- 2 bit regime + 1 bit sign
    constant C_PRODUCT_WIDHT      : integer := 3 * (C_MAX_MANTISSA_WIDTH + 1);
    -- signals
    signal   s_product            : std_logic_vector(C_PRODUCT_WIDHT - 1 downto 0);
    signal   s_efficient_exponent : std_logic_vector(G_Bs + G_ES + 1 downto 0);

begin
    --s_product            <= std_logic_vector(unsigned(i_hidden_fract_a) * unsigned(i_hidden_fract_b));
    -- s_efficient_exponent <= std_logic_vector(signed((0 => i_efficient_exponent_a(G_Bs + G_ES)) & i_efficient_exponent_a) + signed((0 => i_efficient_exponent_b(G_Bs + G_ES)) & i_efficient_exponent_b)); -- + signed(s_msb_mantissa));

    -- o_eff_exp_result <= s_efficient_exponent;
    -- o_mant_product <= s_product;
end architecture Behavioral;
