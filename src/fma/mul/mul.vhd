library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mul_fma is
    generic(
        G_N  : integer := 8;
        G_ES : integer := 2;
        G_Bs : integer
    );
    port(
        i_efficient_exponent_a : in  std_logic_vector(G_Bs + G_ES downto 0);
        i_efficient_exponent_b : in  std_logic_vector(G_Bs + G_ES downto 0);
        i_hidden_fract_a       : in  std_logic_vector(G_N - G_ES - 3 downto 0);
        i_hidden_fract_b       : in  std_logic_vector(G_N - G_ES - 3 downto 0);
        -- outputs
        o_mant_product         : out std_logic_vector((2 * (G_N - G_ES - 3 + 1)) - 1 downto 0);
        o_eff_exp_result       : out std_logic_vector(G_Bs + G_ES downto 0)
    );
end entity mul_fma;

architecture Behavioral of mul_fma is
    -- constant
    constant C_MAX_MANTISSA_WIDTH : integer := G_N - G_ES - 3; -- 2 bit regime + 1 bit sign
    constant C_PRODUCT_WIDHT      : integer := 2 * (C_MAX_MANTISSA_WIDTH + 1);
    -- signals
    signal   s_product            : std_logic_vector(C_PRODUCT_WIDHT - 1 downto 0);
    signal   s_efficient_exponent : std_logic_vector(G_Bs + G_ES  downto 0);

begin
    s_product            <= std_logic_vector(unsigned(i_hidden_fract_a) * unsigned(i_hidden_fract_b));
    s_efficient_exponent <= std_logic_vector(signed(i_efficient_exponent_a) + signed(i_efficient_exponent_b)); -- + signed(s_msb_mantissa));

    o_eff_exp_result <= s_efficient_exponent;
    o_mant_product <= s_product;
end architecture Behavioral;
