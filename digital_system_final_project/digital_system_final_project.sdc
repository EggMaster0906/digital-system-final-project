# The DE2-115 onboard oscillator drives CLOCK_50 at 50 MHz.
create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]
derive_clock_uncertainty

# The LCD controller advances its write state once every 20 us (1,000
# CLOCK_50 cycles).  Its frame, operation, phase, and column registers only
# change on that clock-enable pulse, and LCD_DATA consumes them on a later
# pulse.  Constrain that intentional multicycle path while leaving the
# free-running step counter and the rest of the design at one cycle.
set lcd_step_sources [get_registers {
    lcd_controller:lcd_controller_inst|frame_*
    lcd_controller:lcd_controller_inst|operation*
    lcd_controller:lcd_controller_inst|write_phase*
    lcd_controller:lcd_controller_inst|column[*]
}]
set lcd_data_registers [get_registers {
    lcd_controller:lcd_controller_inst|LCD_DATA[*]
}]
set_multicycle_path -setup 1000 -from $lcd_step_sources -to $lcd_data_registers
set_multicycle_path -hold 999 -from $lcd_step_sources -to $lcd_data_registers

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
set_false_path -to [get_ports {LCD_DATA[*]}]
set_false_path -to [get_ports {LCD_EN LCD_ON LCD_BLON LCD_RS LCD_RW}]
