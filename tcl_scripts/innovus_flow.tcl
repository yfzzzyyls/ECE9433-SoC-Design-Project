# Full Innovus bring-up with timing (MMMC) and initial floorplan
# Assumes innovus_init.tcl is in the same directory and sets up LEF/GDS/netlist/floorplan.

# Resolve paths
set script_dir [file dirname [file normalize [info script]]]
set proj_root  [file normalize [file join $script_dir ..]]

# Source the base init (tech/stdcell/SRAM LEF, netlist, MMMC, floorplan, macro placement, checkpoint)
# MMMC timing views are already loaded during init_design via init_mmmc_file
source [file join $script_dir innovus_init.tcl]

# Use low-effort RC extraction (no tech file required)
setExtractRCMode -engine preRoute -effortLevel low

# Quick timing update (no placement yet)
timeDesign -prePlace

# Save a timed checkpoint
saveDesign [file join $proj_root pd innovus/init_timed.enc]

# ===== PLACEMENT =====
place_design
optDesign -preCTS
timeDesign -preCTS

# ===== CLOCK TREE SYNTHESIS =====
create_ccopt_clock_tree_spec
ccopt_design

# ===== POST-CTS OPTIMIZATION =====
optDesign -postCTS
timeDesign -postCTS

# Save post-CTS checkpoint
saveDesign [file join $proj_root pd innovus/post_cts.enc]
