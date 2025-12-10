# Innovus bring-up script (baseline import/floorplan)
# Paths assume this repo layout and the TSMC16 collateral tree mounted at /ip/tsmc/tsmc16adfp.

# Resolve project root (folder containing this script's parent)
set script_dir [file dirname [file normalize [info script]]]
set proj_root  [file normalize [file join $script_dir ..]]

# Library and design inputs
set TECH_LEF  "/ip/tsmc/tsmc16adfp/source/DAFP0203001_2_X/Executable_Package/Collaterals/Tech/APR/N16ADFP_APR_Innovus/N16ADFP_APR_Innovus_11M.10a.tlef"
set STD_LEF   "/ip/tsmc/tsmc16adfp/source/DAFP0203001_2_X/Executable_Package/Collaterals/IP/stdcell/N16ADFP_StdCell/LEF/lef/N16ADFP_StdCell.lef"
set SRAM_LEF  "/ip/tsmc/tsmc16adfp/source/DAFP0203001_2_X/Executable_Package/Collaterals/IP/sram/N16ADFP_SRAM/LEF/N16ADFP_SRAM_100a.lef"

set STD_GDS   "/ip/tsmc/tsmc16adfp/source/DAFP0203001_2_X/Executable_Package/Collaterals/IP/stdcell/N16ADFP_StdCell/GDS/N16ADFP_StdCell.gds"
set SRAM_GDS  "/ip/tsmc/tsmc16adfp/source/DAFP0203001_2_X/Executable_Package/Collaterals/IP/sram/N16ADFP_SRAM/GDS/N16ADFP_SRAM_100a.gds"

set NETLIST   [file join $proj_root mapped soc_top.v]
set TOP       "soc_top"

# MMMC file for timing setup (legacy syntax for batch mode)
set MMMC_LEGACY_FILE [file normalize [file join $script_dir innovus_mmmc_legacy.tcl]]

# Power nets (adjust if your LEF uses different names)
set init_pwr_net VDD
set init_gnd_net VSS

# Use LEGACY init mode - this is the only mode where floorPlan command exists
set init_lef_file   [list $TECH_LEF $STD_LEF $SRAM_LEF]
set init_verilog    $NETLIST
set init_top_cell   $TOP
set init_mmmc_file  $MMMC_LEGACY_FILE

# Initialize design (timing libraries loaded via init_mmmc_file)
init_design

# Create floorplan - floorPlan command IS available in legacy batch mode
# Ultra-low utilization (30%) for maximum DRC cleanness - course project setting
# Maximum routing space to eliminate short wire segments
floorPlan -site core -r 1.0 0.30 50 50 50 50

# Place and fix the SRAM macro; adjust coordinates/orientation to taste.
set sram_inst [get_db insts u_sram/u_sram_macro]
if { [llength $sram_inst] > 0 } {
  placeInstance $sram_inst 50 50 R0
  set_db $sram_inst .place_status fixed
}

# Save an initial design checkpoint
saveDesign ../pd/innovus/init.enc
