# pio_begin
create_clock -name sys_clock -period 6.666666666666667 [get_ports sys_clock]
create_clock -name bus_clock -period 6.666666666666667 [get_ports bus_clock]
set_false_path -from resetn
# pio_end

derive_pll_clocks -create_base_clocks
