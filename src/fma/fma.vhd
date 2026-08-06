library ieee;
library work;

use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.utility_pkg.all;

entity fma is
    generic(
        G_N  : integer := 8;
        G_ES : integer := 2
    );
    port(
        clk      : in std_logic;
        rst      : in std_logic;
        i_opa    : in  std_logic_vector(G_N - 1 downto 0);
        i_opb    : in  std_logic_vector(G_N - 1 downto 0);
        i_opc    : in  std_logic_vector(G_N - 1 downto 0);
        o_result : out std_logic_vector(7 downto 0)
    );
end entity fma;

architecture RTL of fma is
    constant C_Bs : integer := integer(clog2(G_N)); -- bitwidth for maximal decoded !! regime of G_N-1 bits TODO sollte hier nich ceil sien

    signal s_is_nar : std_logic;
    signal s_sign_a, s_sign_b, s_sign_c, s_sign_t,s_sign_o                                                                           : std_logic;
    signal s_efficient_exponent_a, s_efficient_exponent_b, s_efficient_exponent_c, s_efficient_exponent_t, s_efficient_exponent_o : std_logic_vector(C_Bs + G_ES downto 0);
    signal s_hidden_fract_a, s_hidden_fract_b, s_hidden_fract_c, s_hidden_fract_t                                                 : std_logic_vector(2 * (G_N - G_ES - 3 + 1) - 1 downto 0);
    signal s_hidden_fract_o                                                                                                       : std_logic_vector(2 * (G_N - G_ES - 3 + 1) + 2 downto 0);
    signal s_sticky_bit_o                                                                                                         : std_logic;

begin
    operand_decoder : entity work.decoder
        generic map(
            G_N  => G_N,
            G_ES => G_ES,
            G_Bs => C_Bs
        )
        port map(
            i_op_mul_a             => i_opa,
            i_op_mul_b             => i_opb,
            i_op_add_c             => i_opc,
            o_sign_a               => s_sign_a,
            o_is_nar => s_is_nar,
            o_efficient_exponent_a => s_efficient_exponent_a,
            o_hidden_fract_a       => s_hidden_fract_a,
            o_sign_b               => s_sign_b,
            o_efficient_exponent_b => s_efficient_exponent_b,
            o_hidden_fract_b       => s_hidden_fract_b,
            o_sign_c               => s_sign_c,
            o_efficient_exponent_c => s_efficient_exponent_c,
            o_hidden_fract_c       => s_hidden_fract_c
        );

    multiplier : entity work.multiplier
        generic map(
            G_N  => G_N,
            G_ES => G_ES,
            G_Bs => C_Bs
        )
        port map(
            i_sign_op1       => s_sign_a,
            i_mant_op1       => s_hidden_fract_a,
            i_eff_exp_op1    => s_efficient_exponent_a,
            i_sign_op2       => s_sign_b,
            i_mant_op2       => s_hidden_fract_b,
            i_eff_exp_op2    => s_efficient_exponent_b,
            o_sign_result    => s_sign_t,
            o_mant_result    => s_hidden_fract_t,
            o_eff_exp_result => s_efficient_exponent_t
        );

    adder : entity work.adder
        generic map(
            G_N  => G_N,
            G_ES => G_ES,
            G_Bs => C_Bs
        )
        port map(
            i_sign_op1           => s_sign_a,
            i_mant_op1           => s_hidden_fract_a,
            i_eff_exp_op1        => s_efficient_exponent_a,
            i_sign_op2           => s_sign_c,
            i_mant_op2           => s_hidden_fract_b,
            i_eff_exp_op2        => s_efficient_exponent_b,
            o_sign_result        => s_sign_o,
            o_sticky_result      => s_sticky_bit_o,
            o_mant_result        => s_hidden_fract_o,
            o_eff_exp_add_result => s_efficient_exponent_o
        );

    output_encoder : entity work.encoder
        generic map(
            G_N  => G_N,
            G_ES => G_ES,
            G_Bs => C_Bs
        )
        port map(
            i_is_nar => s_is_nar,
            i_sticky_op1  => s_sticky_bit_o,
            i_sign_op1    => s_sign_o,
            i_mant_op1    => s_hidden_fract_o,
            i_eff_exp_op1 => s_efficient_exponent_o,
            o_result      => o_result
        );

end architecture RTL;
