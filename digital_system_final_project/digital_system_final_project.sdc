# The DE2-115 onboard oscillator drives CLOCK_50 at 50 MHz.
create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]
derive_clock_uncertainty

# KEY[0] is an asynchronous reset input. The LED indicators have no
# external setup/hold requirement, so only register-to-register timing
# is relevant for this stage of the project.
set_false_path -from [get_ports {KEY[0] KEY[1]}]
set_false_path -to [get_ports {LEDR[*]}]
set_false_path -to [get_ports {LEDG[*]}]
set_false_path -to [get_ports {HEX0[*]}]
set_false_path -to [get_ports {HEX1[*]}]
set_false_path -to [get_ports {HEX2[*]}]
set_false_path -to [get_ports {HEX3[*]}]
set_false_path -to [get_ports {HEX4[*]}]
set_false_path -to [get_ports {HEX5[*]}]
set_false_path -to [get_ports {HEX6[*]}]
set_false_path -to [get_ports {HEX7[*]}]
