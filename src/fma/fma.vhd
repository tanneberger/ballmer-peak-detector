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
        i_opa : in  std_logic_vector(G_N - 1 downto 0);
        i_opb : in  std_logic_vector(G_N - 1 downto 0);
        i_opc : in  std_logic_vector(G_N - 1 downto 0);
        o_res : out std_logic_vector(7 downto 0);
    );
end entity fma;

architecture RTL of fma is
    constant C_Bs                 : integer := integer(clog2(G_N)); -- bitwidth for maximal decoded !! regime of G_N-1 bits TODO sollte hier nich ceil sien
    constant C_MAX_MANTISSA_WIDTH : integer := G_N - G_ES - 3; -- 2 bit regime + 1 bit sign

    constant C_INTERNAL_MANTISSA_WIDTH : integer := C_MAX_MANTISSA_WIDTH + 3; -- mantissa + hidden, guard, rounding (and sticky) bit

    signal s_sign_0, s_sign_1, s_sign_2 : std_logic;
    signal s_normalized_operand_0       : std_logic_vector(G_N - 2 downto 0);
    signal s_normalized_operand_1       : std_logic_vector(G_N - 2 downto 0);
    signal s_normalized_operand_2       : std_logic_vector(G_N - 2 downto 0);

    signal s_rc_0, s_rc_1, s_rc_2                   : std_logic;
    signal s_regime_0, s_regime_1, s_regime_2       : std_logic_vector(C_Bs - 1 downto 0);
    signal s_exponent_0, s_exponent_1, s_exponent_2 : std_logic_vector(G_ES - 1 downto 0);
    signal s_mantissa_0, s_mantissa_1, s_mantissa_2 : std_logic_vector(C_MAX_MANTISSA_WIDTH - 1 downto 0);

    signal   s_hidden_mantissa_0, s_hidden_mantissa_1 : std_logic_vector(C_MAX_MANTISSA_WIDTH downto 0);
    constant C_PRODUCT_WIDHT                          : integer := 2 * (C_MAX_MANTISSA_WIDTH + 1);
    signal   s_product                                : std_logic_vector(C_PRODUCT_WIDHT - 1 downto 0);

    signal s_signed_regime_0 : std_logic_vector(C_Bs downto 0);
    signal s_signed_regime_1 : std_logic_vector(C_Bs downto 0);

    signal s_efficient_exponent_0 : std_logic_vector(C_Bs + G_ES downto 0);
    signal s_efficient_exponent_1 : std_logic_vector(C_Bs + G_ES downto 0);
    signal s_efficient_exponent   : std_logic_vector(C_Bs + G_ES + 1 downto 0);
    signal s_op0_greater_op1      : std_logic;

begin
    s_sign_0 <= i_opa(G_N - 1);
    s_sign_1 <= i_opb(G_N - 1);
    s_sign_2 <= i_opc(G_N - 1);

    s_normalized_operand_0 <= std_logic_vector(unsigned(not i_opa(G_N - 2 downto 0)) + 1) when s_sign_0 = '1' else i_opa(G_N - 2 downto 0);
    s_normalized_operand_1 <= std_logic_vector(unsigned(not i_opb(G_N - 2 downto 0)) + 1) when s_sign_1 = '1' else i_opb(G_N - 2 downto 0);
    s_normalized_operand_2 <= std_logic_vector(unsigned(not i_opc(G_N - 2 downto 0)) + 1) when s_sign_2 = '1' else i_opc(G_N - 2 downto 0);

    inst_decoder_0 : entity work.posit_decode
        generic map(
            N  => G_N - 1,
            Bs => C_Bs,
            es => G_ES
        )
        port map(
            in_val => s_normalized_operand_0,
            rc     => s_rc_0,
            regime => s_regime_0,
            exp    => s_exponent_0,
            mant   => s_mantissa_0
        );

    inst_decoder_1 : entity work.posit_decode
        generic map(
            N  => G_N - 1,
            Bs => C_Bs,
            es => G_ES
        )
        port map(
            in_val => s_normalized_operand_1,
            rc     => s_rc_1,
            regime => s_regime_1,
            exp    => s_exponent_1,
            mant   => s_mantissa_1
        );

    inst_decoder_2 : entity work.posit_decode
        generic map(
            N  => G_N - 1,
            Bs => C_Bs,
            es => G_ES
        )
        port map(
            in_val => s_normalized_operand_2,
            rc     => s_rc_1,
            regime => s_regime_2,
            exp    => s_exponent_2,
            mant   => s_mantissa_2
        );

    inst_encoder_0 : entity work.posit_encode
        generic map(
            G_N  => G_N,
            G_ES => G_ES
        )
        port map(
            i_sign               => s_sign_0,
            i_is_inf             => std_logic(0), --TODO
            i_is_zero            => std_logic(0), --TODO
            i_sticky             => std_logic(0), --TODO
            i_normalized_mantissa => s_normalized_operand_0,
            i_efficient_exponent  => s_efficient_exponent_0,
            o_result              => o_res
        );

    s_hidden_mantissa_0 <= '1' & s_mantissa_0;
    s_hidden_mantissa_1 <= '1' & s_mantissa_1;

    s_product <= std_logic_vector(unsigned(s_hidden_mantissa_0) * unsigned(s_hidden_mantissa_1));

    -- efficient exponent calculations
    s_signed_regime_0 <= '0' & s_regime_0 when s_rc_0 = '1' else std_logic_vector(unsigned(not ('0' & s_regime_0)) + 1);
    s_signed_regime_1 <= '0' & s_regime_1 when s_rc_1 = '1' else std_logic_vector(unsigned(not ('0' & s_regime_1)) + 1);

    s_efficient_exponent_0 <= s_signed_regime_0 & s_exponent_0;
    s_efficient_exponent_1 <= s_signed_regime_1 & s_exponent_1;

    s_efficient_exponent <= std_logic_vector(signed((0 => s_efficient_exponent_0(C_Bs + G_ES)) & s_efficient_exponent_0) + signed((0 => s_efficient_exponent_1(C_Bs + G_ES)) & s_efficient_exponent_1)); -- + signed(s_msb_mantissa));

    -------------------------------------- Adder stuff

end architecture RTL;
