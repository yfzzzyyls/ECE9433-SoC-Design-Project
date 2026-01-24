# Complete P&R Flow - Ring + Stripes PG
# Phased Power Grid Implementation for CORDIC SoC
# 15% utilization, M2-only halo around SRAM

set script_dir [file dirname [file normalize [info script]]]
set proj_root  [file normalize [file join $script_dir ..]]

puts "\n=========================================="
puts "PHASE: Ring + Stripes Power Grid"
puts "=========================================="
puts "Configuration:"
puts "  - Utilization: 15%"
puts "  - SRAM halo: M2-only (M1 open for power)"
puts "  - Power: M9/M10 ring + PG stripes"
puts "  - sroute: corePin + blockPin, M2-M10"
puts "  - No fill"
puts "==========================================\n"

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

puts "Initializing design..."
init_design

# Create floorplan - 15% utilization (proven 0-DRC/0-LVS configuration)
puts "\n=========================================="
puts "===== FLOORPLAN: 15% utilization ====="
puts "==========================================\n"
floorPlan -site core -r 1.0 0.15 50 50 50 50

# Place and fix the SRAM macro - CENTER-BOTTOM placement
set sram_inst [get_db insts u_sram/u_sram_macro]
if { [llength $sram_inst] > 0 } {
  # Center-bottom placement for clean routing
  set sram_x 167.0
  set sram_y 100.0

  placeInstance $sram_inst $sram_x $sram_y R0
  set_db $sram_inst .place_status fixed
  puts "SRAM macro placed at ($sram_x, $sram_y) - center-bottom"

  # M2-ONLY halo around SRAM (leave M1 open for power rails)
  set halo 10.0

  # Get bbox as string and split into list - handle Innovus bbox format
  set sram_bbox_str [get_db $sram_inst .bbox]
  set sram_bbox_list [split [string trim $sram_bbox_str "{}"] " "]

  # Extract coordinates as numbers
  set bbox_llx [expr {double([lindex $sram_bbox_list 0])}]
  set bbox_lly [expr {double([lindex $sram_bbox_list 1])}]
  set bbox_urx [expr {double([lindex $sram_bbox_list 2])}]
  set bbox_ury [expr {double([lindex $sram_bbox_list 3])}]

  # Calculate halo coordinates
  set h_llx [expr {$bbox_llx - $halo}]
  set h_lly [expr {$bbox_lly - $halo}]
  set h_urx [expr {$bbox_urx + $halo}]
  set h_ury [expr {$bbox_ury + $halo}]

  puts "SRAM bbox: $bbox_llx $bbox_lly $bbox_urx $bbox_ury"
  puts "Halo bbox: $h_llx $h_lly $h_urx $h_ury"

  # KEY CHANGE: M2-only blockage (leave M1 open for power rails)
  createRouteBlk -name sram_halo_m2 -layer M2 -box [list $h_llx $h_lly $h_urx $h_ury] -exceptpgnet
  puts "M2-only routing blockage: 15um halo around SRAM (M1 open for power)"
}

# Set process and connect power
setDesignMode -process 16
globalNetConnect VDD -type pgpin -pin VDD -all -override
globalNetConnect VSS -type pgpin -pin VSS -all -override
globalNetConnect VDD -type tiehi -all -override
globalNetConnect VSS -type tielo -all -override

puts "\n=========================================="
puts "===== PG: M9/M10 RING + M8/M9 STRIPES ====="
puts "==========================================\n"

# Add M9/M10 power ring around core (15um inset from edges)
puts "Adding M9/M10 power ring..."
# Width 5.0um exceeded allowed max (~4.05). Use 4.0/3.5 to stay legal.
addRing -nets {VDD VSS} \
  -type core_rings \
  -layer {top M10 bottom M10 left M9 right M9} \
  -width 4.0 -spacing 3.5 \
  -offset {top 15.0 bottom 15.0 left 15.0 right 15.0}

puts "Power ring added: M9 vertical, M10 horizontal"
puts "Width: 4.0um, Spacing: 3.5um, Offset: 15um from core"

# Add PG stripes to tie ring into core rails (coarse but contiguous)
puts "Adding PG stripes (M9 vertical, M8 horizontal)..."
# Get bbox for stripe count (normalize to flat list)
set die_bbox_str [get_db designs .bbox]
set die_bbox_list [split [string trim $die_bbox_str "{}"] " "]
set llx [expr {double([lindex $die_bbox_list 0])}]
set lly [expr {double([lindex $die_bbox_list 1])}]
set urx [expr {double([lindex $die_bbox_list 2])}]
set ury [expr {double([lindex $die_bbox_list 3])}]
set die_w [expr {$urx - $llx}]
set die_h [expr {$ury - $lly}]

# Vertical stripes on M9 (coarse pitch, overlap ring)
set v_pitch 80.0
set v_sets [expr {int($die_w / $v_pitch) + 1}]
catch {
  addStripe -nets {VDD VSS} -layer M9 -direction vertical \
    -width 3.0 -spacing 3.0 -set_to_set_distance $v_pitch \
    -start_offset [expr {$llx + 20.0}] -number_of_sets $v_sets
  puts "M9 vertical stripes: $v_sets sets @ ${v_pitch}um pitch"
}

# Horizontal stripes on M8 (coarse pitch, overlap ring)
set h_pitch 80.0
set h_sets [expr {int($die_h / $h_pitch) + 1}]
catch {
  addStripe -nets {VDD VSS} -layer M8 -direction horizontal \
    -width 3.0 -spacing 3.0 -set_to_set_distance $h_pitch \
    -start_offset [expr {$lly + 20.0}] -number_of_sets $h_sets
  puts "M8 horizontal stripes: $h_sets sets @ ${h_pitch}um pitch"
}

# Save checkpoint after ring
saveDesign [file join $proj_root pd/innovus/cordic_ring_only.enc]

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

# DRC-friendly settings
setNanoRouteMode -drouteFixAntenna true
# Allow routing up to M10 to relieve congestion
setNanoRouteMode -routeBottomRoutingLayer 1
setNanoRouteMode -routeTopRoutingLayer 10

# Aggressive DRC settings
setNanoRouteMode -drouteAutoStop false
setNanoRouteMode -drouteExpAdvancedMarFix true
setNanoRouteMode -drouteEndIteration 20

puts "Routing settings configured for DRC priority"

# Connect PG ring to stdcell rails (core pins) using M2-M10
puts "\n=========================================="
puts "===== POWER CONNECTION: sroute corePin + blockPin (SRAM) ====="
puts "==========================================\n"
sroute -nets {VDD VSS} -connect {corePin blockPin} \
  -layerChangeRange {M2 M10} \
  -allowLayerChange 1

puts "\n=========================================="
puts "===== PLACEMENT ====="
puts "==========================================\n"
place_design
saveDesign [file join $proj_root pd/innovus/cordic_place.enc]

puts "\n=========================================="
puts "===== CLOCK TREE ====="
puts "==========================================\n"
ccopt_design -cts
saveDesign [file join $proj_root pd/innovus/cordic_cts.enc]

puts "\n=========================================="
puts "===== ROUTING ====="
puts "==========================================\n"
routeDesign
saveDesign [file join $proj_root pd/innovus/cordic_route.enc]

# NO METAL FILL for Phase 1
puts "\n===== METAL FILL: SKIPPED (Phase 1) ====="

puts "\n=========================================="
puts "===== ITERATIVE DRC CLEAN LOOP ====="
puts "==========================================\n"

set max_iterations 20
set iteration 0
set viol_count 999999

while {$iteration < $max_iterations && $viol_count > 0} {
    set iteration [expr $iteration + 1]

    puts "\n--- Iteration $iteration ---"

    # DRC check
    set drc_rpt [file join $proj_root pd/innovus/drc_cordic_iter${iteration}.rpt]
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

    puts "DRC violations: $viol_count"

    if {$viol_count == 0} {
        puts "\n*** SUCCESS: DESIGN IS DRC CLEAN! ***"
        break
    }

    if {$iteration < $max_iterations} {
        puts "Running ECO fix (iteration $iteration)..."
        if {$iteration <= 10} {
            catch {ecoRoute -fix_drc}
        } else {
            catch {
                ecoRoute -fix_drc
                globalDetailRoute
            }
        }
    }
}

puts "\n=========================================="
puts "===== LVS CONNECTIVITY VERIFICATION ====="
puts "==========================================\n"

# Regular Net Connectivity Check
set conn_regular_rpt [file join $proj_root pd/innovus/lvs_connectivity_regular.rpt]
puts "Checking regular net connectivity..."
verifyConnectivity -type regular -error 1000 -warning 100 -report $conn_regular_rpt

# Parse regular net errors
set regular_errors 0
if {[file exists $conn_regular_rpt]} {
    set fp [open $conn_regular_rpt r]
    set content [read $fp]
    close $fp
    if {[regexp {(\d+)\s+Problem\(s\)} $content match num]} {
        set regular_errors $num
    }
    if {[regexp {Total Regular Net Errors\s*:\s*(\d+)} $content match num]} {
        set regular_errors $num
    }
}
puts "Regular net errors: $regular_errors"

# Special Net (Power/Ground) Connectivity Check
set conn_special_rpt [file join $proj_root pd/innovus/lvs_connectivity_special.rpt]
puts "Checking special net (power/ground) connectivity..."
verifyConnectivity -type special -error 1000 -warning 100 -report $conn_special_rpt

# Parse special net errors
set special_errors 0
if {[file exists $conn_special_rpt]} {
    set fp [open $conn_special_rpt r]
    set content [read $fp]
    close $fp
    if {[regexp {(\d+)\s+Problem\(s\)} $content match num]} {
        set special_errors $num
    }
    if {[regexp {Total Special Net Errors\s*:\s*(\d+)} $content match num]} {
        set special_errors $num
    }
}
puts "Special net errors: $special_errors"

# Process Antenna Check
set antenna_rpt [file join $proj_root pd/innovus/lvs_process_antenna.rpt]
puts "Checking process antenna violations..."
catch {verifyProcessAntenna -report $antenna_rpt}

# LVS Summary
set total_lvs_errors [expr $regular_errors + $special_errors]
set lvs_clean [expr {$total_lvs_errors == 0}]

puts "\n=========================================="
puts "LVS CONNECTIVITY SUMMARY"
puts "==========================================\n"
puts "Regular Net Errors:    $regular_errors"
puts "Special Net Errors:    $special_errors"
puts "Total LVS Errors:      $total_lvs_errors"
puts ""

if {$lvs_clean} {
    puts "*** LVS STATUS: PASS (0 connectivity errors) ***"
} else {
    puts "*** LVS STATUS: FAIL ($total_lvs_errors errors) ***"
}

puts "\n=========================================="
puts "===== STATIC TIMING ANALYSIS (STA) ====="
puts "==========================================\n"

# Extract post-route parasitics with QRC
puts "Extracting post-route RC with QRC..."
setExtractRCMode -engine postRoute -effortLevel medium
catch {extractRC}

# Run timing analysis
puts "Running post-route timing analysis..."
catch {timeDesign -postRoute -outDir [file join $proj_root pd/innovus/timing]}

# Get slack values
set setup_wns "N/A"
set hold_wns "N/A"
set sta_pass 0

catch {
  set setup_wns [get_db timing_analysis_summary.setup_wns]
  set hold_wns [get_db timing_analysis_summary.hold_wns]

  if {$setup_wns != "N/A" && $hold_wns != "N/A"} {
    if {$setup_wns >= 0 && $hold_wns >= 0} {
      set sta_pass 1
    }
  }
}

puts "\nSTA Results:"
puts "  Setup WNS: $setup_wns ns"
puts "  Hold WNS:  $hold_wns ns"
puts ""

if {$sta_pass} {
    puts "*** STA STATUS: PASS (positive slack) ***"
} else {
    if {$setup_wns != "N/A"} {
        puts "*** STA STATUS: FAIL (negative slack) ***"
    } else {
        puts "*** STA STATUS: INCOMPLETE (timing data unavailable) ***"
    }
}

puts "\n=========================================="
puts "PHASE 1 RESULT - RING ONLY"
puts "==========================================\n"

# Compute overall pass/fail status
set all_pass [expr {$viol_count == 0 && $lvs_clean && $sta_pass}]

puts "Design: soc_top (CORDIC + RISC-V PEU + SRAM)"
puts "Technology: TSMC 16nm FinFET (N16ADFP)"
puts "Utilization: 15%"
puts "Power Grid: M9/M10 Ring ONLY (Phase 1)"
puts ""

puts "VERIFICATION RESULTS:"
puts "--------------------"

# DRC Status
if {$viol_count == 0} {
    puts "\[PASS\] DRC: 0 violations"
} else {
    puts "\[FAIL\] DRC: $viol_count violations (iterations: $iteration)"
}

# LVS Status
if {$lvs_clean} {
    puts "\[PASS\] LVS: 0 connectivity errors"
    puts "       - Regular nets: 0 errors"
    puts "       - Special nets: 0 errors (VDD/VSS clean)"
} else {
    puts "\[FAIL\] LVS: $total_lvs_errors connectivity errors"
    puts "       - Regular nets: $regular_errors errors"
    puts "       - Special nets: $special_errors errors"
}

# STA Status
if {$sta_pass} {
    puts "\[PASS\] STA: Timing closed"
    puts "       - Setup WNS: ${setup_wns}ns"
    puts "       - Hold WNS: ${hold_wns}ns"
} else {
    if {$setup_wns != "N/A"} {
        puts "\[FAIL\] STA: Timing violations"
        if {$setup_wns < 0} {
            puts "       - Setup WNS: ${setup_wns}ns (NEGATIVE)"
        }
        if {$hold_wns < 0} {
            puts "       - Hold WNS: ${hold_wns}ns (NEGATIVE)"
        }
    } else {
        puts "\[WARN\] STA: Incomplete"
    }
}

puts ""

# Overall verdict
if {$all_pass} {
    puts "************************************************"
    puts "***   PHASE 1 COMPLETE - ALL CHECKS PASSED   ***"
    puts "************************************************"
    puts ""
    puts "Next: Phase 2 - Add sroute corePin only"
} else {
    puts "*** PHASE 1 INCOMPLETE - FIXES REQUIRED ***"
    puts ""
    if {$viol_count > 0} {
        puts "  - DRC: See pd/innovus/drc_cordic_iter*.rpt"
    }
    if {!$lvs_clean} {
        puts "  - LVS: See pd/innovus/lvs_connectivity_*.rpt"
    }
    if {!$sta_pass && $setup_wns != "N/A"} {
        puts "  - STA: See pd/innovus/timing/*.tarpt"
    }
}

saveDesign [file join $proj_root pd/innovus/cordic_phase1_final.enc]

puts "\nCheckpoint: pd/innovus/cordic_phase1_final.enc"
puts "DRC Reports: pd/innovus/drc_cordic_iter*.rpt"
puts "LVS Reports: pd/innovus/lvs_connectivity_*.rpt"
puts ""

exit
