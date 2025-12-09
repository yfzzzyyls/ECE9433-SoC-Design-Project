# Innovus DRC checking and fixing script
# Run after routeDesign completes

set script_dir [file dirname [file normalize [info script]]]
set proj_root  [file normalize [file join $script_dir ..]]

puts "\n=========================================="
puts "Running Innovus DRC Checks"
puts "==========================================\n"

# Get actual die area (bbox is {llx lly urx ury})
set bbox [get_db designs .bbox]
set llx [lindex $bbox 0]
set lly [lindex $bbox 1]
set urx [lindex $bbox 2]
set ury [lindex $bbox 3]
puts "Die area: ($llx,$lly) to ($urx,$ury)"

# Add metal fill if not already done
puts "Adding metal fill..."
addMetalFill -layer {M1 M2 M3 M4 M5 M6} -timingAware sta -area [list $llx $lly $urx $ury]

# Run DRC verification
puts "\nRunning verify_drc..."
verify_drc -limit 10000 -report [file join $proj_root pd/innovus/drc_violations.rpt]

# Get DRC violation summary
set drc_viols [get_db drc_errors]
set num_viols [llength $drc_viols]

puts "\n=========================================="
puts "DRC Summary"
puts "==========================================\n"
puts "Total DRC violations: $num_viols"

if {$num_viols > 0} {
    puts "\nViolation types:"
    # Group violations by type
    set viol_types [dict create]
    foreach viol $drc_viols {
        set vtype [get_db $viol .error_type]
        if {[dict exists $viol_types $vtype]} {
            dict incr viol_types $vtype
        } else {
            dict set viol_types $vtype 1
        }
    }

    dict for {type count} $viol_types {
        puts "  $type: $count violations"
    }

    puts "\nDRC violations saved to: pd/innovus/drc_violations.rpt"
} else {
    puts "\n*** DESIGN IS DRC CLEAN! ***"
}

puts "\n=========================================="
puts "Saving post-DRC design..."
saveDesign [file join $proj_root pd/innovus/post_drc.enc]

puts "\nDRC check complete!"
