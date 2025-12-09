# Basic timing constraints matching synthesis (non-topo)
create_clock -name clk -period 10 [get_ports clk]
set_clock_uncertainty 0.1 [get_clocks clk]

set in_ports [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
if {[sizeof_collection $in_ports] > 0} {
  set_input_delay 1 -clock clk $in_ports
}

set_output_delay 1 -clock clk [all_outputs]

# Don’t time through async reset
set_false_path -through [get_ports rst_n]
