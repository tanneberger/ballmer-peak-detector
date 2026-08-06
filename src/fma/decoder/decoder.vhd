library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity decoder is
    generic(
        G_N  : integer := 8;
        G_ES : integer := 2;
        G_Bs : integer
    );
    port(
        i_op_mul_a             : in  std_logic_vector(G_N - 1 downto 0);
        i_op_mul_b             : in  std_logic_vector(G_N - 1 downto 0);
        i_op_add_c             : in  std_logic_vector(G_N - 1 downto 0);
        -- outputs
        o_efficient_exponent_a : out std_logic_vector(G_Bs + G_ES downto 0);
        o_efficient_exponent_b : out std_logic_vector(G_Bs + G_ES downto 0);
        o_efficient_exponent_c : out std_logic_vector(G_Bs + G_ES downto 0);
        o_hidden_fract_a       : out std_logic_vector(G_N - G_ES - 3 downto 0);
        o_hidden_fract_b       : out std_logic_vector(G_N - G_ES - 3 downto 0);
        o_hidden_fract_c       : out std_logic_vector(G_N - G_ES - 3 downto 0)
    );
end entity;

architecture Behavioral of decoder is
    -- constant
    constant C_MAX_MANTISSA_WIDTH : integer := G_N - G_ES - 3;
    -- signals
    signal s_sign_0, s_sign_1, s_sign_2 : std_logic;
    signal s_normalized_operand_0       : std_logic_vector(G_N - 2 downto 0);
    signal s_normalized_operand_1       : std_logic_vector(G_N - 2 downto 0);
    signal s_normalized_operand_2       : std_logic_vector(G_N - 2 downto 0);

    signal s_rc_0, s_rc_1, s_rc_2                   : std_logic;
    signal s_regime_0, s_regime_1, s_regime_2       : std_logic_vector(G_Bs - 1 downto 0);
    signal s_exponent_0, s_exponent_1, s_exponent_2 : std_logic_vector(G_ES - 1 downto 0);
    signal s_mantissa_0, s_mantissa_1, s_mantissa_2 : std_logic_vector(C_MAX_MANTISSA_WIDTH - 1 downto 0);

    signal s_signed_regime_0 : std_logic_vector(G_Bs downto 0);
    signal s_signed_regime_1 : std_logic_vector(G_Bs downto 0);
    signal s_signed_regime_2 : std_logic_vector(G_Bs downto 0);

    signal s_efficient_exponent_0 : std_logic_vector(G_Bs + G_ES downto 0);
    signal s_efficient_exponent_1 : std_logic_vector(G_Bs + G_ES downto 0);
    signal s_efficient_exponent_2 : std_logic_vector(G_Bs + G_ES downto 0);
begin
    s_sign_0 <= i_op_mul_a(G_N - 1);
    s_sign_1 <= i_op_mul_b(G_N - 1);
    s_sign_2 <= i_op_add_c(G_N - 1);

    s_normalized_operand_0 <= std_logic_vector(unsigned(not i_op_mul_a(G_N - 2 downto 0)) + 1) when s_sign_0 = '1' else i_op_mul_a(G_N - 2 downto 0);
    s_normalized_operand_1 <= std_logic_vector(unsigned(not i_op_mul_b(G_N - 2 downto 0)) + 1) when s_sign_1 = '1' else i_op_mul_b(G_N - 2 downto 0);
    s_normalized_operand_2 <= std_logic_vector(unsigned(not i_op_add_c(G_N - 2 downto 0)) + 1) when s_sign_2 = '1' else i_op_add_c(G_N - 2 downto 0);

    inst_decoder_0 : entity work.posit_decode
        generic map(
            N  => G_N - 1,
            Bs => G_Bs,
            es => G_ES
        )
        port map(
            i_val    => s_normalized_operand_0,
            o_rc     => s_rc_0,
            o_regime => s_regime_0,
            o_exp    => s_exponent_0,
            o_mant   => s_mantissa_0
        );

    inst_decoder_1 : entity work.posit_decode
        generic map(
            N  => G_N - 1,
            Bs => G_Bs,
            es => G_ES
        )
        port map(
            i_val    => s_normalized_operand_1,
            o_rc     => s_rc_1,
            o_regime => s_regime_1,
            o_exp    => s_exponent_1,
            o_mant   => s_mantissa_1
        );

    inst_decoder_2 : entity work.posit_decode
        generic map(
            N  => G_N - 1,
            Bs => G_Bs,
            es => G_ES
        )
        port map(
            i_val    => s_normalized_operand_2,
            o_rc     => s_rc_2,
            o_regime => s_regime_2,
            o_exp    => s_exponent_2,
            o_mant   => s_mantissa_2
        );

    s_signed_regime_0 <= '0' & s_regime_0 when s_rc_0 = '1' else std_logic_vector(unsigned(not ('0' & s_regime_0)) + 1);
    s_signed_regime_1 <= '0' & s_regime_1 when s_rc_1 = '1' else std_logic_vector(unsigned(not ('0' & s_regime_1)) + 1);
    s_signed_regime_2 <= '0' & s_regime_2 when s_rc_2 = '1' else std_logic_vector(unsigned(not ('0' & s_regime_2)) + 1);

    o_efficient_exponent_a <= s_signed_regime_0 & s_exponent_0;
    o_efficient_exponent_b <= s_signed_regime_1 & s_exponent_1;
    o_efficient_exponent_c <= s_signed_regime_1 & s_exponent_1;

    o_hidden_fract_a <= '1' & s_mantissa_0;
    o_hidden_fract_b <= '1' & s_mantissa_1;
    o_hidden_fract_c <= '1' & s_mantissa_2;

end architecture Behavioral;
