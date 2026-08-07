library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fma is
    generic(
        G_N  : integer := 8;
        G_ES : integer := 2
    );
    port(
        i_clk : std_logic;
        i_opa    : in  std_logic_vector(G_N - 1 downto 0);
        i_opb    : in  std_logic_vector(G_N - 1 downto 0);
        i_opc    : in  std_logic_vector(G_N - 1 downto 0);
        o_result : out std_logic_vector(G_N-1 downto 0)
    );
end entity fma;

architecture Structural of fma is
    signal s_mul_res : std_logic_vector(G_N-1 downto 0);
begin
    posit_mul_inst : entity work.posit_mul
        generic map(
            G_N  => G_N,
            G_ES => G_ES
        )
        port map(
            i_operand_0 => i_opa,
            i_operand_1 => i_opb,
            o_result    => s_mul_res
        );
    
    posit_add_inst : entity work.posit_add
        generic map(
            G_N  => G_N,
            G_ES => G_ES
        )
        port map(
            i_operand_0 => s_mul_res,
            i_operand_1 => i_opc,
            o_result    => o_result
        );
    
end architecture Structural;
