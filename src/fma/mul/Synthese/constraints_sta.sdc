###############################################################################
# Created by write_sdc
# Wed Aug  5 12:28:05 2026
###############################################################################
current_design posit_mul
###############################################################################
# Timing Constraints
###############################################################################
create_clock -name i_clk -period 10.0000 [get_ports {i_clk}]
set_clock_transition 0.0200 [get_clocks {i_clk}]
set_clock_uncertainty 0.0500 i_clk
set_input_delay 0.0000 -clock [get_clocks {i_clk}] -add_delay [get_ports {i_enable}]
set_input_delay 0.0000 -clock [get_clocks {i_clk}] -add_delay [get_ports {i_operand_0[0]}]
set_input_delay 0.0000 -clock [get_clocks {i_clk}] -add_delay [get_ports {i_operand_0[1]}]
set_input_delay 0.0000 -clock [get_clocks {i_clk}] -add_delay [get_ports {i_operand_0[2]}]
set_input_delay 0.0000 -clock [get_clocks {i_clk}] -add_delay [get_ports {i_operand_0[3]}]
set_input_delay 0.0000 -clock [get_clocks {i_clk}] -add_delay [get_ports {i_operand_0[4]}]
set_input_delay 0.0000 -clock [get_clocks {i_clk}] -add_delay [get_ports {i_operand_0[5]}]
set_input_delay 0.0000 -clock [get_clocks {i_clk}] -add_delay [get_ports {i_operand_0[6]}]
set_input_delay 0.0000 -clock [get_clocks {i_clk}] -add_delay [get_ports {i_operand_0[7]}]
set_input_delay 0.0000 -clock [get_clocks {i_clk}] -add_delay [get_ports {i_operand_1[0]}]
set_input_delay 0.0000 -clock [get_clocks {i_clk}] -add_delay [get_ports {i_operand_1[1]}]
set_input_delay 0.0000 -clock [get_clocks {i_clk}] -add_delay [get_ports {i_operand_1[2]}]
set_input_delay 0.0000 -clock [get_clocks {i_clk}] -add_delay [get_ports {i_operand_1[3]}]
set_input_delay 0.0000 -clock [get_clocks {i_clk}] -add_delay [get_ports {i_operand_1[4]}]
set_input_delay 0.0000 -clock [get_clocks {i_clk}] -add_delay [get_ports {i_operand_1[5]}]
set_input_delay 0.0000 -clock [get_clocks {i_clk}] -add_delay [get_ports {i_operand_1[6]}]
set_input_delay 0.0000 -clock [get_clocks {i_clk}] -add_delay [get_ports {i_operand_1[7]}]
set_output_delay 0.0000 -clock [get_clocks {i_clk}] -add_delay [get_ports {o_result[0]}]
set_output_delay 0.0000 -clock [get_clocks {i_clk}] -add_delay [get_ports {o_result[1]}]
set_output_delay 0.0000 -clock [get_clocks {i_clk}] -add_delay [get_ports {o_result[2]}]
set_output_delay 0.0000 -clock [get_clocks {i_clk}] -add_delay [get_ports {o_result[3]}]
set_output_delay 0.0000 -clock [get_clocks {i_clk}] -add_delay [get_ports {o_result[4]}]
set_output_delay 0.0000 -clock [get_clocks {i_clk}] -add_delay [get_ports {o_result[5]}]
set_output_delay 0.0000 -clock [get_clocks {i_clk}] -add_delay [get_ports {o_result[6]}]
set_output_delay 0.0000 -clock [get_clocks {i_clk}] -add_delay [get_ports {o_result[7]}]
###############################################################################
# Environment
###############################################################################
set_load -pin_load 0.0461 [get_ports {o_result[7]}]
set_load -pin_load 0.0461 [get_ports {o_result[6]}]
set_load -pin_load 0.0461 [get_ports {o_result[5]}]
set_load -pin_load 0.0461 [get_ports {o_result[4]}]
set_load -pin_load 0.0461 [get_ports {o_result[3]}]
set_load -pin_load 0.0461 [get_ports {o_result[2]}]
set_load -pin_load 0.0461 [get_ports {o_result[1]}]
set_load -pin_load 0.0461 [get_ports {o_result[0]}]
set_driving_cell -lib_cell sg13g2_inv_16 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {i_clk}]
set_driving_cell -lib_cell sg13g2_inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {i_enable}]
set_driving_cell -lib_cell sg13g2_inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {i_operand_0[7]}]
set_driving_cell -lib_cell sg13g2_inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {i_operand_0[6]}]
set_driving_cell -lib_cell sg13g2_inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {i_operand_0[5]}]
set_driving_cell -lib_cell sg13g2_inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {i_operand_0[4]}]
set_driving_cell -lib_cell sg13g2_inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {i_operand_0[3]}]
set_driving_cell -lib_cell sg13g2_inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {i_operand_0[2]}]
set_driving_cell -lib_cell sg13g2_inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {i_operand_0[1]}]
set_driving_cell -lib_cell sg13g2_inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {i_operand_0[0]}]
set_driving_cell -lib_cell sg13g2_inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {i_operand_1[7]}]
set_driving_cell -lib_cell sg13g2_inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {i_operand_1[6]}]
set_driving_cell -lib_cell sg13g2_inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {i_operand_1[5]}]
set_driving_cell -lib_cell sg13g2_inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {i_operand_1[4]}]
set_driving_cell -lib_cell sg13g2_inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {i_operand_1[3]}]
set_driving_cell -lib_cell sg13g2_inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {i_operand_1[2]}]
set_driving_cell -lib_cell sg13g2_inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {i_operand_1[1]}]
set_driving_cell -lib_cell sg13g2_inv_2 -pin {Y} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {i_operand_1[0]}]
###############################################################################
# Design Rules
###############################################################################
set_max_fanout 10.0000 [current_design]
