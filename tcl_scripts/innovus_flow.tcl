# Full Innovus bring-up with timing (MMMC) and initial floorplan
# Assumes innovus_init.tcl is in the same directory and sets up LEF/GDS/netlist/floorplan.

# Resolve paths
set script_dir [file dirname [file normalize [info script]]]
set proj_root  [file normalize [file join $script_dir ..]]

# Source the base init (tech/stdcell/SRAM LEF, netlist, MMMC, floorplan, macro placement, checkpoint)
# MMMC timing views are already loaded during init_design via init_mmmc_file
source [file join $script_dir innovus_init.tcl]

# Quick timing update (no placement yet)
timeDesign -prePlace

# Save a timed checkpoint
saveDesign [file join $proj_root pd innovus/init_timed.enc]
