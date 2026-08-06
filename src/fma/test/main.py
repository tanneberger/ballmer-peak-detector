# test_my_design.py (extended)

import cocotb
from cocotb.triggers import FallingEdge, Timer


async def generate_clock(dut):
    """Generate clock pulses."""

    for _ in range(10):
        dut.clk.value = 0
        await Timer(1, unit="ns")
        dut.clk.value = 1
        await Timer(1, unit="ns")


@cocotb.test()
async def my_second_test(dut):
    dut.clk.value = 1#not dut.clk.value

    dut.i_opa.value = 12
    dut.i_opb.value = 12
    dut.i_opc.value = 12

    await Timer(10, unit="ns")  # wait a bit
    #await FallingEdge(dut.clk)  # wait for falling edge/"negedge"

    cocotb.log.info("my_signal_1 is %s", dut.o_result.value)
    #assert dut.my_signal_2.value == 0
