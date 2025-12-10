# Complete P&R Flow with QRC Tech Files
# Uses freshly synthesized netlist from synthesis with STARRC tech files
# Industry standard flow: DC synthesis with STARRC → Innovus P&R with QRC

set script_dir [file dirname [file normalize [info script]]]
set proj_root  [file normalize [file join $script_dir ..]]

puts "\n=========================================="
puts "Complete P&R Flow with QRC Tech Files"
puts "Industry Standard Practice"
puts "==========================================\n"
puts "Using netlist from: mapped_with_tech/"
puts "Tech files: QRC for parasitic extraction"
puts ""

# Library and design inputs
set TECH_LEF  "/ip/tsmc/tsmc16adfp/source/DAFP0203001_2_X/Executable_Package/Collaterals/Tech/APR/N16ADFP_APR_Innovus/N16ADFP_APR_Innovus_11M.10a.tlef"
set STD_LEF   "/ip/tsmc/tsmc16adfp/source/DAFP0203001_2_X/Executable_Package/Collaterals/IP/stdcell/N16ADFP_StdCell/LEF/lef/N16ADFP_StdCell.lef"
set SRAM_LEF  "/ip/tsmc/tsmc16adfp/source/DAFP0203001_2_X/Executable_Package/Collaterals/IP/sram/N16ADFP_SRAM/LEF/N16ADFP_SRAM_100a.lef"

# Use netlist from synthesis with STARRC tech
set NETLIST   [file join $proj_root mapped_with_tech soc_top.v]
set TOP       "soc_top"

# MMMC file with QRC
set MMMC_QRC_FILE [file normalize [file join $script_dir innovus_mmmc_legacy_qrc.tcl]]

# Power nets
set init_pwr_net VDD
set init_gnd_net VSS

# Initialize design with QRC-enabled MMMC
set init_lef_file   [list $TECH_LEF $STD_LEF $SRAM_LEF]
set init_verilog    $NETLIST
set init_top_cell   $TOP
set init_mmmc_file  $MMMC_QRC_FILE

puts "Initializing design with QRC tech files..."
init_design

# Create floorplan - 30% utilization for DRC cleanness
floorPlan -site core -r 1.0 0.30 50 50 50 50

# Place and fix the SRAM macro
set sram_inst [get_db insts u_sram/u_sram_macro]
if { [llength $sram_inst] > 0 } {
  placeInstance $sram_inst 50 50 R0
  set_db $sram_inst .place_status fixed
}

# Set process and connect power
setDesignMode -process 16
globalNetConnect VDD -type pgpin -pin VDD -all -override
globalNetConnect VSS -type pgpin -pin VSS -all -override
globalNetConnect VDD -type tiehi -all -override
globalNetConnect VSS -type tielo -all -override

puts "\n=========================================="
puts "DRC-Optimized Routing Settings"
puts "==========================================\n"

# DRC-focused routing settings
setNanoRouteMode -droutePostRouteSpreadWire true
setNanoRouteMode -routeWithViaInPin true
setNanoRouteMode -routeWithViaOnlyForStandardCellPin true
setNanoRouteMode -drouteUseMultiCutViaEffort high

# Disable timing optimization for pure DRC focus
setNanoRouteMode -routeWithSiDriven false
setNanoRouteMode -routeWithTimingDriven false

# Additional DRC-friendly settings
setNanoRouteMode -drouteFixAntenna true
setNanoRouteMode -routeBottomRoutingLayer 1
setNanoRouteMode -routeTopRoutingLayer 6

puts "  - Post-route wire spreading: ENABLED"
puts "  - Via-in-pin routing: ENABLED"
puts "  - Multi-cut via effort: HIGH"
puts "  - Timing-driven: DISABLED (DRC priority)"
puts "  - QRC extraction: ENABLED"

puts "\n=========================================="
puts "===== PLACEMENT ====="
puts "==========================================\n"
place_design
saveDesign [file join $proj_root pd/innovus/complete_place.enc]

puts "\n=========================================="
puts "===== CLOCK TREE ====="
puts "==========================================\n"
ccopt_design -cts
saveDesign [file join $proj_root pd/innovus/complete_cts.enc]

puts "\n=========================================="
puts "===== ROUTING (DRC-Optimized) ====="
puts "==========================================\n"
routeDesign
saveDesign [file join $proj_root pd/innovus/complete_route.enc]

puts "\n=========================================="
puts "===== METAL FILL ====="
puts "==========================================\n"
set bbox [get_db designs .bbox]
set llx [lindex $bbox 0]
set lly [lindex $bbox 1]
set urx [lindex $bbox 2]
set ury [lindex $bbox 3]

puts "Die area: ($llx, $lly) to ($urx, $ury)"

addMetalFill -layer {M1 M2 M3 M4 M5 M6} -timingAware sta -area "$llx $lly $urx $ury"

puts "\n=========================================="
puts "===== FIRST DRC CHECK ====="
puts "==========================================\n"

# Write DRC report to file
set drc_rpt [file join $proj_root pd/innovus/drc_complete_1.rpt]
verify_drc -limit 10000 -report $drc_rpt

# Parse report to count violations
set viol_count 0
if {[file exists $drc_rpt]} {
    set fp [open $drc_rpt r]
    set content [read $fp]
    close $fp
    if {[regexp {Total Violations\s*:\s*(\d+)} $content match num]} {
        set viol_count $num
    }
}

puts "\nFirst DRC check: $viol_count violations"

# Initialize viol_count2
set viol_count2 $viol_count

if {$viol_count > 0} {
    puts "\n=========================================="
    puts "===== ECO FIX ATTEMPT ====="
    puts "==========================================\n"

    # Try ECO route to fix violations
    puts "Attempting ecoRoute with DRC fix..."
    catch {ecoRoute -fix_drc}

    # Second DRC check
    set drc_rpt2 [file join $proj_root pd/innovus/drc_complete_2.rpt]
    verify_drc -limit 10000 -report $drc_rpt2

    set viol_count2 0
    if {[file exists $drc_rpt2]} {
        set fp [open $drc_rpt2 r]
        set content [read $fp]
        close $fp
        if {[regexp {Total Violations\s*:\s*(\d+)} $content match num]} {
            set viol_count2 $num
        }
    }

    puts "After ECO route: $viol_count2 violations"
}

puts "\n=========================================="
puts "FINAL RESULT - COMPLETE TECH-AWARE FLOW"
puts "==========================================\n"

if {$viol_count2 == 0} {
    puts "*** SUCCESS: DESIGN IS DRC CLEAN! ***"
    puts "Final violation count: 0"
    puts ""
    puts "Complete Flow Summary:"
    puts "  1. DC Synthesis with STARRC tech files"
    puts "  2. Innovus P&R with QRC tech files"
    puts "  3. DRC verification: 0 violations"
    puts ""
    puts "Industry standard tech-aware flow COMPLETE!"
} else {
    puts "Final violation count: $viol_count2"
    if {$viol_count2 < $viol_count} {
        puts "Violations reduced from $viol_count to $viol_count2"
    }
}

saveDesign [file join $proj_root pd/innovus/complete_final.enc]

puts "\nCheckpoint: pd/innovus/complete_final.enc"
puts "DRC Reports: pd/innovus/drc_complete_*.rpt"
puts "Netlist source: mapped_with_tech/soc_top.v\n"

exit
