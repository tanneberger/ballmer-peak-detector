library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity add_fma is
    generic(
        G_N  : integer := 8;
        G_ES : integer := 2;
        G_Bs : integer
    );
    port(
        i_mant_product_mul   : in  std_logic_vector((2 * (G_N - G_ES - 3 + 1)) - 1 downto 0);
        i_eff_exp_mul        : in  std_logic_vector(G_Bs + G_ES + 1 downto 0);
        i_mant_c             : in  std_logic_vector((2 * (G_N - G_ES - 3 + 1)) - 1 downto 0);
        i_eff_exp_c          : in  std_logic_vector(G_Bs + G_ES + 1 downto 0);
        -- outputs
        o_mant_add_result    : out std_logic_vector((2 * (G_N - G_ES - 3 + 1)) - 1 downto 0);
        o_eff_exp_add_result : out std_logic_vector(G_Bs + G_ES + 1 downto 0)
    );
end entity add_fma;

architecture Behavioral of add_fma is
    -- constant
    constant C_MAX_MANTISSA_WIDTH : integer := G_N - G_ES - 3; -- 2 bit regime + 1 bit sign
    constant C_PRODUCT_WIDHT      : integer := 2 * (C_MAX_MANTISSA_WIDTH + 1);
    -- signals
    
begin

end architecture Behavioral;
