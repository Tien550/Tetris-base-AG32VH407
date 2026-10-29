# pio_begin
if { ! [info exists ::HSI_PERIOD] } {
  set ::HSI_PERIOD 100.0
}
create_clock -name PIN_HSI -period $::HSI_PERIOD [get_ports PIN_HSI]
set_clock_groups -asynchronous -group PIN_HSI
if { ! [info exists ::HSE_PERIOD] } {
  set ::HSE_PERIOD 125.0
}
create_clock -name PIN_HSE -period $::HSE_PERIOD [get_ports PIN_HSE]
set_clock_groups -asynchronous -group PIN_HSE
if { ! [info exists ::OSC_PERIOD] } {
  set ::OSC_PERIOD 125.0
}
create_clock -name PIN_OSC -period $::OSC_PERIOD [get_ports PIN_OSC]
set_clock_groups -asynchronous -group PIN_OSC
derive_pll_clocks -create_base_clocks
set_false_path -from rv32|resetn_out
# pio_end

set inst      *
set ahb_clock pll_inst|*clk*0*
set hbus_clk  pll_inst|*clk*3*

if { [info exists ::MODE] && $::MODE == "NATIVE" } {
  set suffix _reg
} else {
  set suffix ""
}

create_generated_clock -name hbus_clk_out -source hbus_clk90_out_data_gclk|outclk [get_ports hbus_clk_out]
create_generated_clock -name rwds_clk_src -source hbus_clk_out
create_generated_clock -name rwds_clk     -source hbus_clk_out [get_ports hbus_rwds]

# For FIFOs
if { [info exists ::MODE] && $::MODE == "NATIVE" } {
  set_false_path -from $inst|WrPtrGrayD* -to $inst|WrPtrGrayRs*
  set_false_path -from $inst|RdPtrGray*  -to $inst|RdPtrGrayWs*
} else {
  set_false_path -from $inst|delayed_wrptr_g* -to $inst|rs_dgwp*
  set_false_path -from $inst|rdptr_g*         -to $inst|ws_dgrp*
}

# rwds_reg latches data from memory, not from hbus_clk
set_false_path -from $hbus_clk -to $inst|rwds_reg*

# rwds_clk_src to rwds_clk, for input timing
set_input_delay -clock rwds_clk_src -max  0.4ns [get_ports "hbus_adq* hbus_rwds"]
set_input_delay -clock rwds_clk_src -min -0.4ns [get_ports "hbus_adq* hbus_rwds"]
set_input_delay -clock rwds_clk_src -max  0.4ns [get_ports "hbus_adq* hbus_rwds"] -clock_fall -add_delay
set_input_delay -clock rwds_clk_src -min -0.4ns [get_ports "hbus_adq* hbus_rwds"] -clock_fall -add_delay

set_multicycle_path -from rwds_clk_src -to rwds_clk -setup 0
set_multicycle_path -from rwds_clk_src -to rwds_clk -hold  -1
set_false_path -rise_from rwds_clk_src -fall_to rwds_clk -setup
set_false_path -fall_from rwds_clk_src -rise_to rwds_clk -setup
set_false_path -rise_from rwds_clk_src -rise_to rwds_clk -hold
set_false_path -fall_from rwds_clk_src -fall_to rwds_clk -hold

# hbus_clk to hbus_clk_out, for output timing
set_output_delay -max 0.5 [get_ports "hbus_adq* hbus_rwds"] -clock hbus_clk_out -add_delay
set_output_delay -max 0.5 [get_ports "hbus_adq* hbus_rwds"] -clock hbus_clk_out -add_delay -clock_fall
set_output_delay -min 0.5 [get_ports "hbus_adq* hbus_rwds"] -clock hbus_clk_out -add_delay
set_output_delay -min 0.5 [get_ports "hbus_adq* hbus_rwds"] -clock hbus_clk_out -add_delay -clock_fall

set_output_delay -max 0 [get_ports "hbus_csn"] -clock hbus_clk_out -add_delay
set_output_delay -min 0 [get_ports "hbus_csn"] -clock hbus_clk_out -add_delay

# ahb_clock to hbus_clk
set_multicycle_path -from $inst|ahb_rstn_reg* -to $hbus_clk -setup 2
set_multicycle_path -from $inst|ahb_rstn_reg* -to $hbus_clk -hold  1

set_multicycle_path -from [get_clocks $ahb_clock] -to [get_registers $inst|hbus_running$suffix] -setup 2
set_multicycle_path -from [get_clocks $ahb_clock] -to [get_registers $inst|hbus_running$suffix] -hold  1

set_multicycle_path -from $inst|ahb_seq$suffix -to $inst|hbus_seq$suffix -setup 2
set_multicycle_path -from $inst|ahb_seq$suffix -to $inst|hbus_seq$suffix -hold  1

set_multicycle_path -from $inst|in_fifo_half_full* -to $inst|clk_oe* -setup 2
set_multicycle_path -from $inst|in_fifo_half_full* -to $inst|clk_oe* -hold  1

set_multicycle_path -from $inst|ahb_ca* -to $inst|hbus_ca* -setup 2
set_multicycle_path -from $inst|ahb_ca* -to $inst|hbus_ca* -hold  1

# hbus_clk to ahb_clock
set_multicycle_path -from $inst|hbus_running$suffix -to $inst|ahb_running$suffix -setup 2
set_multicycle_path -from $inst|hbus_running$suffix -to $inst|ahb_running$suffix -hold  1

set_multicycle_path -from $inst|hbus_running$suffix -to $inst|ahb_trigger$suffix -setup 2
set_multicycle_path -from $inst|hbus_running$suffix -to $inst|ahb_trigger$suffix -hold  1

set_multicycle_path -from [get_registers $inst|in_fifo_wrreq_rst*] -to [get_clocks $ahb_clock] -setup 2
set_multicycle_path -from [get_registers $inst|in_fifo_wrreq_rst*] -to [get_clocks $ahb_clock] -hold  2

# ahb_clock to rwds_clk
set_multicycle_path -from $inst|in_fifo_reset* -to rwds_clk -setup 2
set_multicycle_path -from $inst|in_fifo_reset* -to rwds_clk -hold  2

# hbus_clk to rwds_clk
set_multicycle_path -from $inst|in_fifo_wrreq_rst* -to rwds_clk -setup 2
set_multicycle_path -from $inst|in_fifo_wrreq_rst* -to rwds_clk -hold  2

# rwds_clk to hbus_clk
set_multicycle_path -from rwds_clk -to $hbus_clk -setup 2
set_multicycle_path -from rwds_clk -to $hbus_clk -hold  1
