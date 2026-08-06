import cocotb
from cocotb.triggers import FallingEdge, Timer
import random
import softposit as sp
from softposit import posit8

@cocotb.test()
async def random_posit_test(dut):
    
    for i in range(10):
        dut.clk.value = 0

        a = random.random() * 10
        b = random.random() * 10
        c = random.random() * 10
        
        p_2_a = posit8(a)
        p_2_b = posit8(b)
        p_2_c = posit8(c)

        dut.i_opa.value = int(p_2_a)
        dut.i_opb.value = int(p_2_b)
        dut.i_opc.value = int(p_2_c)
        dut.clk.value = 1
        await Timer(200, unit="ns")  # wait a bit
        
        expected_value = p_2_c.fma(p_2_a, p_2_b)
        received_value = posit8(bits=dut.o_result.value.integer)
        cocotb.log.info("%f * %f + %f = %s = %s", a, b, c, str(expected_value), str(received_value))
        p_2_a.toBinary()
        p_2_b.toBinary()
        p_2_c.toBinary()
        expected_value.toBinary()
        received_value.toBinary()
        
    #await FallingEdge(dut.clk)  # wait for falling edge/"negedge"

    #assert dut.my_signal_2.value == 0
