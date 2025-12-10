# Complete DC Synthesis with STARRC Tech Files - Industry Standard Flow
# Full flow from RTL to mapped netlist with parasitic-aware synthesis

set proj_root [file normalize [pwd]]

puts "\n=========================================="
puts "DC Synthesis with STARRC Tech Files"
puts "Complete Flow from RTL"
puts "Industry Standard Practice"
puts "==========================================\n"

# Design setup
set top_module "soc_top"
set clock_period 10.0

# RTL sources
set rtl_files [list \
    "$proj_root/rtl/soc_top.sv" \
    "$proj_root/rtl/sram.sv" \
    "$proj_root/rtl/peu.sv" \
    "$proj_root/rtl/interconnect.sv" \
    "$proj_root/third_party/picorv32/picorv32.v" \
]

# Technology libraries - USE .db (compiled) FORMAT
set std_db "/ip/tsmc/tsmc16adfp/source/DAFP0203001_2_X/Executable_Package/Collaterals/IP/stdcell/N16ADFP_StdCell/NLDM/N16ADFP_StdCelltt0p8v25c.db"
set sram_db "/ip/tsmc/tsmc16adfp/source/DAFP0203001_2_X/Executable_Package/Collaterals/IP/sram/N16ADFP_SRAM/NLDM/N16ADFP_SRAM_tt0p8v0p8v25c_100a.db"

# STARRC tech file for parasitic estimation (industry standard)
set starrc_tech "/ip/tsmc/tsmc16adfp/tech/RC/N16ADFP_STARRC/N16ADFP_STARRC_worst.nxtgrd"

# Output directory
set out_dir "$proj_root/mapped_with_tech"
file mkdir $out_dir

puts "Configuration:"
puts "  Top Module: $top_module"
puts "  Clock Period: ${clock_period}ns"
puts ""
puts "RTL Sources:"
foreach f $rtl_files {
    puts "  - [file tail $f]"
}
puts ""

# Setup libraries
set target_library [list $std_db $sram_db]
set link_library [concat "* " $target_library]
set synthetic_library "dw_foundation.sldb"

set_app_var search_path [list $proj_root/rtl $proj_root/third_party/picorv32]

puts "Technology Libraries:"
puts "  Stdcell DB: [file tail $std_db]"
puts "  SRAM DB: [file tail $sram_db]"
if {[file exists $starrc_tech]} {
    puts "  STARRC Tech: [file tail $starrc_tech]"
    puts "  -> Parasitic-aware synthesis ENABLED"
} else {
    puts "  WARNING: STARRC tech file not found"
}
puts ""

# Read RTL
puts "=========================================="
puts "Reading RTL files..."
puts "==========================================\n"
define_design_lib WORK -path ./WORK
analyze -format sverilog $rtl_files
elaborate $top_module
current_design $top_module
link

puts "\n=========================================="
puts "Design Hierarchy"
puts "==========================================\n"
report_hierarchy

# Apply constraints
puts "\n=========================================="
puts "Applying Timing Constraints"
puts "==========================================\n"
create_clock -name clk -period $clock_period [get_ports clk]
set_input_delay  [expr $clock_period * 0.2] -clock clk [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay [expr $clock_period * 0.2] -clock clk [all_outputs]
set_load 0.01 [all_outputs]
set_driving_cell -lib_cell BUFFD1BWP16P90LVT [all_inputs]

# Set operating conditions
set_operating_conditions WCCOM

# Check for timing violations before compile
check_timing
check_design

puts "\n=========================================="
puts "Compiling Design"
puts "==========================================\n"
puts "Using compile_ultra for advanced optimization..."
puts "This may take 5-10 minutes..."
puts ""

# Compile with ultra optimization
compile_ultra -no_autoungroup

puts "\n=========================================="
puts "Compilation Complete"
puts "==========================================\n"

# Generate comprehensive reports
puts "Generating reports..."

report_timing -max_paths 10 -transition_time -nets -attributes -nosplit > $out_dir/timing.rpt
report_area -hierarchy -nosplit > $out_dir/area.rpt
report_power -nosplit > $out_dir/power.rpt
report_constraint -all_violators -nosplit > $out_dir/constraints_violators.rpt
report_qor > $out_dir/qor.rpt

# Write outputs
puts "\nWriting netlist and constraints..."
change_names -rules verilog -hierarchy
write -format verilog -hierarchy -output $out_dir/soc_top.v
write -format ddc -hierarchy -output $out_dir/soc_top.ddc
write_sdc $out_dir/soc_top.sdc

# Summary
puts "\n=========================================="
puts "Synthesis Complete with Tech Files!"
puts "==========================================\n"
puts "Outputs:"
puts "  Directory: $out_dir/"
puts "  - soc_top.v (mapped netlist)"
puts "  - soc_top.ddc (binary database)"
puts "  - soc_top.sdc (timing constraints)"
puts "  - timing.rpt"
puts "  - area.rpt"
puts "  - power.rpt"
puts "  - qor.rpt"
puts ""

# Quick summary
set area [get_attribute [current_design] area]
puts "Design Area: [format "%.2f" $area] um^2"
puts ""
puts "Next step: Run Innovus P&R with QRC tech files"
puts "==========================================\n"

exit
