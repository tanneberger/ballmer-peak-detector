###############################################################################
# Created by write_sdc
###############################################################################
current_design fma
###############################################################################
# Timing Constraints
###############################################################################
create_clock -name vclk -period 40.0000 
set_input_delay 0.0000 -clock [get_clocks {vclk}] -add_delay [get_ports {i_opa[0]}]
set_input_delay 0.0000 -clock [get_clocks {vclk}] -add_delay [get_ports {i_opa[1]}]
set_input_delay 0.0000 -clock [get_clocks {vclk}] -add_delay [get_ports {i_opa[2]}]
set_input_delay 0.0000 -clock [get_clocks {vclk}] -add_delay [get_ports {i_opa[3]}]
set_input_delay 0.0000 -clock [get_clocks {vclk}] -add_delay [get_ports {i_opa[4]}]
set_input_delay 0.0000 -clock [get_clocks {vclk}] -add_delay [get_ports {i_opa[5]}]
set_input_delay 0.0000 -clock [get_clocks {vclk}] -add_delay [get_ports {i_opa[6]}]
set_input_delay 0.0000 -clock [get_clocks {vclk}] -add_delay [get_ports {i_opa[7]}]
set_input_delay 0.0000 -clock [get_clocks {vclk}] -add_delay [get_ports {i_opb[0]}]
set_input_delay 0.0000 -clock [get_clocks {vclk}] -add_delay [get_ports {i_opb[1]}]
set_input_delay 0.0000 -clock [get_clocks {vclk}] -add_delay [get_ports {i_opb[2]}]
set_input_delay 0.0000 -clock [get_clocks {vclk}] -add_delay [get_ports {i_opb[3]}]
set_input_delay 0.0000 -clock [get_clocks {vclk}] -add_delay [get_ports {i_opb[4]}]
set_input_delay 0.0000 -clock [get_clocks {vclk}] -add_delay [get_ports {i_opb[5]}]
set_input_delay 0.0000 -clock [get_clocks {vclk}] -add_delay [get_ports {i_opb[6]}]
set_input_delay 0.0000 -clock [get_clocks {vclk}] -add_delay [get_ports {i_opb[7]}]
set_input_delay 0.0000 -clock [get_clocks {vclk}] -add_delay [get_ports {i_opc[0]}]
set_input_delay 0.0000 -clock [get_clocks {vclk}] -add_delay [get_ports {i_opc[1]}]
set_input_delay 0.0000 -clock [get_clocks {vclk}] -add_delay [get_ports {i_opc[2]}]
set_input_delay 0.0000 -clock [get_clocks {vclk}] -add_delay [get_ports {i_opc[3]}]
set_input_delay 0.0000 -clock [get_clocks {vclk}] -add_delay [get_ports {i_opc[4]}]
set_input_delay 0.0000 -clock [get_clocks {vclk}] -add_delay [get_ports {i_opc[5]}]
set_input_delay 0.0000 -clock [get_clocks {vclk}] -add_delay [get_ports {i_opc[6]}]
set_input_delay 0.0000 -clock [get_clocks {vclk}] -add_delay [get_ports {i_opc[7]}]
set_output_delay 0.0000 -clock [get_clocks {vclk}] -add_delay [get_ports {o_result[0]}]
set_output_delay 0.0000 -clock [get_clocks {vclk}] -add_delay [get_ports {o_result[1]}]
set_output_delay 0.0000 -clock [get_clocks {vclk}] -add_delay [get_ports {o_result[2]}]
set_output_delay 0.0000 -clock [get_clocks {vclk}] -add_delay [get_ports {o_result[3]}]
set_output_delay 0.0000 -clock [get_clocks {vclk}] -add_delay [get_ports {o_result[4]}]
set_output_delay 0.0000 -clock [get_clocks {vclk}] -add_delay [get_ports {o_result[5]}]
set_output_delay 0.0000 -clock [get_clocks {vclk}] -add_delay [get_ports {o_result[6]}]
set_output_delay 0.0000 -clock [get_clocks {vclk}] -add_delay [get_ports {o_result[7]}]
###############################################################################
# Environment
###############################################################################
###############################################################################
# Design Rules
###############################################################################
