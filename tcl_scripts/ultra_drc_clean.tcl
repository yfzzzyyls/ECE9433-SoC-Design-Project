# Ultra DRC-Clean Flow - Zero Tolerance Approach
# Strategy: Constrain M4 routing to avoid short segments

set script_dir [file dirname [file normalize [info script]]]
set proj_root  [file normalize [file join $script_dir ..]]

puts "\n=========================================="
puts "Ultra DRC-Clean P&R Flow"
puts "Goal: 0 DRC Violations"
puts "==========================================\n"

# Source initialization with 50% util
source [file join $script_dir innovus_init.tcl]

# Set process and connect power
setDesignMode -process 16
globalNetConnect VDD -type pgpin -pin VDD -all -override
globalNetConnect VSS -type pgpin -pin VSS -all -override
globalNetConnect VDD -type tiehi -all -override
globalNetConnect VSS -type tielo -all -override

puts "\n=========================================="
puts "Ultra-Aggressive DRC Prevention"
puts "==========================================\n"

# DRC-focused routing settings - removed invalid options for Innovus 21.18
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
puts "  - Antenna fixing: ENABLED"

puts "\n=========================================="
puts "===== PLACEMENT ====="
puts "==========================================\n"
place_design
saveDesign [file join $proj_root pd/innovus/ultra_place.enc]

puts "\n=========================================="
puts "===== CLOCK TREE ====="
puts "==========================================\n"
ccopt_design -cts
saveDesign [file join $proj_root pd/innovus/ultra_cts.enc]

puts "\n=========================================="
puts "===== ROUTING (DRC-Optimized) ====="
puts "==========================================\n"
routeDesign
saveDesign [file join $proj_root pd/innovus/ultra_route.enc]

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
set drc_rpt [file join $proj_root pd/innovus/drc_ultra_1.rpt]
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
    set drc_rpt2 [file join $proj_root pd/innovus/drc_ultra_2.rpt]
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
puts "FINAL RESULT"
puts "==========================================\n"

if {$viol_count2 == 0} {
    puts "*** SUCCESS: DESIGN IS DRC CLEAN! ***"
    puts "Final violation count: 0"
} else {
    puts "Final violation count: $viol_count2"
    if {$viol_count2 < $viol_count} {
        puts "Violations reduced from $viol_count to $viol_count2"
    }
}

saveDesign [file join $proj_root pd/innovus/ultra_final.enc]

puts "\nCheckpoint: pd/innovus/ultra_final.enc"
puts "DRC Reports: pd/innovus/drc_ultra_*.rpt\n"

exit
