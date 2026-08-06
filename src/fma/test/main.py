import cocotb
from cocotb.triggers import FallingEdge, Timer
#import random
#import softposit as sp
#from softposit import posit8

@cocotb.test()
async def random_posit_test(dut):
    
    with open("testdata.csv", "rw") as f:
        for line in f.readlines():
            line_split = line.split(" ")
            dut.clk.value = 0

            a = int(line_split[0], 16)
            b = int(line_split[1], 16)
            c = int(line_split[2], 16)
            expected = int(line_split[3], 16)
            
            dut.i_opa.value = a
            dut.i_opb.value = b
            dut.i_opc.value = c
            dut.clk.value = 1
            await Timer(200, unit="ns")  # wait a bit
            
            cocotb.log.info("%i * %i + %i = %i = %i", a, b, c, expected, dut.o_result.value.integer)
       
    #await FallingEdge(dut.clk)  # wait for falling edge/"negedge"

    #assert dut.my_signal_2.value == 0
