# Override this variable to use a VHDL toplevel instead of SystemVerilog
TOPLEVEL_LANG ?= vhdl

COCOTB_TOPLEVEL = fma

PWD=$(shell pwd)
SRC=$(PWD)/..

VHDL_SOURCES    =  \
	$(SRC)/util/utility_pkg.vhd \
	$(SRC)/util/LOD_T.vhd \
	$(SRC)/add/add.vhd \
	$(SRC)/decoder/posit_decode.vhd \
	$(SRC)/decoder/decoder.vhd \
	$(SRC)/encoder/sticky_shifter_det.vhd \
	$(SRC)/encoder/encoder.vhd \
	$(SRC)/fma.vhd \
	$(SRC)/mul/mul.vhd \
	$(SRC)/fma.vhd

COCOTB_TEST_MODULES=main

include $(shell cocotb-config --makefiles)/Makefile.sim
