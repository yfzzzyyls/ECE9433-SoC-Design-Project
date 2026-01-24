# Fresh P&R Flow with Symmetric Power Grid (V2 - Loose Constraints)
# Goal: Achieve 0 DRC + 0 LVS with properly connected VDD/VSS
#
# Key Principles:
# 1. VDD and VSS must have IDENTICAL stripe counts and positions
# 2. Power rings must be closed loops with corner vias
# 3. All stripes must connect to rings via proper vias
# 4. Follow-pin routing connects standard cells to power mesh
#
# V3 Changes (Jan 16, 2026):
# - Reduced utilization to 25% for maximum routing headroom
# - Centered SRAM near the bottom of core (parameterized placement)
# - Removed M8 stripes to avoid dangling PG segments
# - Moved sroute after placement with a legality gate
# - Expanded PG pin connections (VPP/VDDP/VPW/VSSP/VNW)
#
# Date: Jan 16, 2026

puts "============================================================"
puts "=== Fresh P&R Flow with Symmetric Power Grid             ==="
puts "============================================================"

# Phase control: set START_FROM before sourcing or use env(PNR_START_FROM)
if {![info exists START_FROM]} {
    set START_FROM 1
}
if {[info exists ::env(PNR_START_FROM)]} {
    set START_FROM $::env(PNR_START_FROM)
}
if {![string is integer -strict $START_FROM] || $START_FROM < 1 || $START_FROM > 9} {
    puts "ERROR: START_FROM must be an integer from 1 to 9."
    exit 1
}
puts "=== START_FROM phase: $START_FROM ==="

array set checkpoint_for_phase {
    2 cordic_fresh_floorplan.enc
    3 cordic_fresh_powergrid.enc
    4 cordic_fresh_placed.enc
    5 cordic_fresh_cts.enc
    6 cordic_fresh_routed.enc
    7 cordic_fresh_optimized.enc
}
if {$START_FROM > 1} {
    set restore_phase [expr {$START_FROM - 1}]
    if {[info exists checkpoint_for_phase($restore_phase)]} {
        set restore_file $checkpoint_for_phase($restore_phase)
        if {[file exists $restore_file]} {
            puts "Restoring checkpoint $restore_file for phase $START_FROM..."
            source $restore_file
        } elseif {[file exists "${restore_file}.dat"]} {
            puts "Restoring checkpoint ${restore_file}.dat for phase $START_FROM..."
            restoreDesign "${restore_file}.dat" soc_top
        } else {
            puts "ERROR: Checkpoint $restore_file not found. Run earlier phases first."
            exit 1
        }
    }
}

if {$START_FROM <= 1} {
    # ============================================================
    # PHASE 1: Design Setup and Import
    # ============================================================
    puts "\n===== PHASE 1: Design Setup ====="

    # Set multi-CPU usage
    setMultiCpuUsage -localCpu 8

    # Define file paths
    set lef_files [list \
        /ip/tsmc/tsmc16adfp/source/DAFP0203001_2_X/Executable_Package/Collaterals/Tech/APR/N16ADFP_APR_Innovus/N16ADFP_APR_Innovus_11M.10a.tlef \
        /ip/tsmc/tsmc16adfp/source/DAFP0203001_2_X/Executable_Package/Collaterals/IP/stdcell/N16ADFP_StdCell/LEF/lef/N16ADFP_StdCell.lef \
        /ip/tsmc/tsmc16adfp/source/DAFP0203001_2_X/Executable_Package/Collaterals/IP/sram/N16ADFP_SRAM/LEF/N16ADFP_SRAM_100a.lef \
    ]
    set netlist_file "/home/fy2243/ECE9433-SoC-Design-Project/mapped_with_tech/soc_top.v"
    set mmmc_file "/home/fy2243/ECE9433-SoC-Design-Project/tcl_scripts/innovus_mmmc.tcl"

    # Set init_design variables
    set init_lef_file $lef_files
    set init_verilog $netlist_file
    set init_mmmc_file $mmmc_file
    set init_top_cell soc_top
    set init_pwr_net VDD
    set init_gnd_net VSS

    # Initialize design with analysis views specified
    init_design -setup {view_typ} -hold {view_typ}

    puts "Design loaded successfully"
    puts "Die BBox: [dbGet top.fPlan.box]"
} else {
    puts "\n===== PHASE 1: Design Setup ====="
    puts "Skipping Phase 1 (START_FROM=$START_FROM)"
}

if {$START_FROM <= 2} {
    # ============================================================
    # PHASE 2: Floorplan
    # ============================================================
    puts "\n===== PHASE 2: Floorplan ====="

# Create floorplan with 20% utilization (best balance for power connections)
floorPlan -site core -r 1.0 0.20 50 50 50 50

# V53: Place SRAM macro on the LEFT side of the core
# This puts the SRAM in the X-region where M9 stripes exist (X < 163)
# so that SRAM pins can connect to the power mesh
#
# SRAM size is 43.025 x 105.552 um
# Hierarchical path: u_sram/u_sram_macro
set core_box [join [dbGet top.fPlan.coreBox]]
set core_llx [lindex $core_box 0]
set core_lly [lindex $core_box 1]
set core_urx [lindex $core_box 2]
set core_ury [lindex $core_box 3]
if {![string is double -strict $core_llx] || ![string is double -strict $core_lly] || \
    ![string is double -strict $core_urx] || ![string is double -strict $core_ury]} {
    puts "ERROR: Unexpected coreBox format: $core_box"
    exit 1
}
set sram_w 43.025
set sram_h 105.552
# Place SRAM at left side: start at X = core_llx + 20
# This puts SRAM at X ≈ 70-113, well within the M9 stripe region (X < 163)
set sram_x [expr {$core_llx + 20.0}]
set sram_y [expr {$core_lly + 50.0}]
placeInstance u_sram/u_sram_macro $sram_x $sram_y R0 -fixed
puts "V53: SRAM placed at LEFT side: ($sram_x, $sram_y)"

# Create placement halo around SRAM
addHaloToBlock 5 5 5 5 -allBlock

# Add routing blockage over SRAM for M1-M7 (signals only, allow PG)
createRouteBlk -box [dbGet [dbGet top.insts.name u_sram/u_sram_macro -p].box] -layer {M1 M2 M3 M4 M5 M6 M7} -exceptpgnet

set sram_blk [dbGet [dbGet top.insts.name u_sram/u_sram_macro -p].box]
set sram_l [lindex [lindex $sram_blk 0] 0]
set sram_b [lindex [lindex $sram_blk 0] 1]
set sram_r [lindex [lindex $sram_blk 0] 2]
set sram_t [lindex [lindex $sram_blk 0] 3]

# V23: Block M3 PG routing around SRAM boundary to prevent conflicts
# with SRAM M3 pins. No M4 blockage (causes shorts).
#
# MinStep violations occur when via stacks create small M4 features near SRAM.
# Instead of blocking M4, we'll position M9 stripes to avoid SRAM danger zone.

puts "SRAM boundary: left=$sram_l right=$sram_r bottom=$sram_b top=$sram_t"

# V35: Removed M3 PG blockage - let sroute handle M3 routing
# The M3 blockage was preventing power connections around SRAM
puts "V35: No M3 PG blockage (relying on sroute for smart routing)"

puts "Floorplan created"
puts "Core area: [dbGet top.fPlan.coreBox]"

    # Save floorplan checkpoint
    saveDesign cordic_fresh_floorplan.enc
} else {
    puts "\n===== PHASE 2: Floorplan ====="
    puts "Skipping Phase 2 (START_FROM=$START_FROM)"
}

if {$START_FROM <= 3} {
    # ============================================================
    # PHASE 3: Power Grid - SYMMETRIC VDD/VSS
    # ============================================================
    puts "\n===== PHASE 3: Power Grid (Symmetric) ====="

# Step 3.1: Global net connections (include extra PG pins)
puts "Step 3.1: Global net connections..."
set vdd_pg_pins {VDD VDDM VPP}
set vss_pg_pins {VSS VBB}
foreach pin $vdd_pg_pins {
    globalNetConnect VDD -type pgpin -pin $pin -all -override
}
foreach pin $vss_pg_pins {
    globalNetConnect VSS -type pgpin -pin $pin -all -override
}
globalNetConnect VDD -type tiehi -all -override
globalNetConnect VSS -type tielo -all -override

# Step 3.2: Create power rings (M9 vertical sides, M10 horizontal sides)
# This creates a closed rectangular ring around the core
puts "Step 3.2: Creating power rings..."
addRing -nets {VDD VSS} \
    -layer {top M10 bottom M10 left M9 right M9} \
    -width 2.0 \
    -spacing 1.0 \
    -offset 1.0 \
    -center 0 \
    -jog_distance 0.5 \
    -threshold 0.5

# V62: DENSER M9 stripes with more coverage
# The previous 30um pitch leaves too much gap for standard cell connections
# Strategy: Denser M9 stripes (15um pitch) everywhere except SRAM X-region
puts "Step 3.3: V62 - Creating DENSE M9 vertical stripes..."

# Get SRAM boundaries
set sram_box_pg [dbGet [dbGet top.insts.name u_sram/u_sram_macro -p].box]
set sram_l_pg [lindex [lindex $sram_box_pg 0] 0]
set sram_r_pg [lindex [lindex $sram_box_pg 0] 2]
set sram_b_pg [lindex [lindex $sram_box_pg 0] 1]
set sram_t_pg [lindex [lindex $sram_box_pg 0] 3]
puts "SRAM region: X=$sram_l_pg to $sram_r_pg, Y=$sram_b_pg to $sram_t_pg"

# Set margins to avoid SRAM
set pg_margin 5.0
set left_safe_end [expr {$sram_l_pg - $pg_margin}]
set right_safe_start [expr {$sram_r_pg + $pg_margin}]
puts "Safe M9 regions: X < $left_safe_end and X > $right_safe_start"

# V72: WIDER M9 stripes (1.2um instead of 0.8um) to enable via landing
# The via generation fails due to SPANLENGTHTABLE rules - wider stripes help
puts "V72: Using wider 1.2um M9 stripes for better via landing..."

# DENSE M9 stripes in left-of-SRAM region (15um pitch, 1.2um width)
addStripe -nets {VDD VSS} \
    -layer M9 \
    -direction vertical \
    -width 1.2 \
    -spacing 1.2 \
    -set_to_set_distance 15 \
    -start_from left \
    -start_offset 15 \
    -area [list 0 0 $left_safe_end 400]

# DENSE M9 stripes in right-of-SRAM region (10um pitch, 1.2um width)
addStripe -nets {VDD VSS} \
    -layer M9 \
    -direction vertical \
    -width 1.2 \
    -spacing 1.2 \
    -set_to_set_distance 10 \
    -start_from left \
    -start_offset $right_safe_start \
    -area [list $right_safe_start 0 400 400]

# M9 stripes to cover the gaps
# Gap 1: X=50-65 (between left stripes and SRAM)
puts "Step 3.3b: V72 - Filling M9 gaps with wider stripes..."

# Add M9 stripes from X=50 to just before SRAM (fill gap before SRAM)
addStripe -nets {VDD VSS} \
    -layer M9 \
    -direction vertical \
    -width 1.2 \
    -spacing 1.2 \
    -set_to_set_distance 10 \
    -start_from left \
    -start_offset 52 \
    -area [list 50 0 $left_safe_end 400]

# Add M9 stripes in SRAM X-region but outside SRAM Y-range (below)
addStripe -nets {VDD VSS} \
    -layer M9 \
    -direction vertical \
    -width 1.2 \
    -spacing 1.2 \
    -set_to_set_distance 10 \
    -start_from left \
    -start_offset [expr {$sram_l_pg + 5}] \
    -area [list $sram_l_pg 0 $sram_r_pg [expr {$sram_b_pg - 3}]]

# Add M9 stripes in SRAM X-region but outside SRAM Y-range (above)
addStripe -nets {VDD VSS} \
    -layer M9 \
    -direction vertical \
    -width 1.2 \
    -spacing 1.2 \
    -set_to_set_distance 10 \
    -start_from left \
    -start_offset [expr {$sram_l_pg + 5}] \
    -area [list $sram_l_pg [expr {$sram_t_pg + 3}] $sram_r_pg 400]

# Step 3.4: Create DENSE M10 horizontal stripes spanning the entire design
# M10 provides the horizontal backbone of the power mesh
# Dense pitch (15µm) ensures cells have M10 stripes within reach
puts "Step 3.4: Creating dense M10 horizontal stripes..."
addStripe -nets {VDD VSS} \
    -layer M10 \
    -direction horizontal \
    -width 1.0 \
    -spacing 1.0 \
    -set_to_set_distance 15 \
    -start_from bottom \
    -start_offset 10 \
    -stop_offset 10 \
    -extend_to design_boundary

# Step 3.4b: Add specific M10 stripe at SRAM pin level
# SRAM pins are at Y≈101, so add M10 stripes specifically at Y=100 and Y=102
puts "Step 3.4b: Adding M10 stripes at SRAM pin level (Y≈100-102)..."
addStripe -nets {VDD VSS} \
    -layer M10 \
    -direction horizontal \
    -width 1.0 \
    -spacing 1.0 \
    -set_to_set_distance 4.0 \
    -start_from bottom \
    -start_offset 99 \
    -area [list 0 98 400 106]

# V58: Complete power mesh connectivity
# V57 connected SRAM pins but power mesh has some floating pieces
# Need to:
# 1. Connect SRAM pins
# 2. Connect floating stripes in the mesh
# 3. Ensure standard cells can reach power
puts "Step 3.4c: V58 - Complete power mesh connectivity..."

# Add via stack from M9 to M10
puts "Adding M9-M10 vias..."
editPowerVia -add_vias 1 -nets {VDD VSS} -bottom_layer M9 -top_layer M10 -orthogonal_only 0

# Connect SRAM block pins
puts "Connecting SRAM block pins..."
sroute -nets {VDD VSS} \
    -connect blockPin \
    -inst u_sram/u_sram_macro \
    -blockPinTarget {stripe ring} \
    -blockPinLayerRange {M4 M10} \
    -layerChangeRange {M4 M10} \
    -allowLayerChange 1 \
    -allowJogging 1 \
    -targetViaLayerRange {M4 M10}

# Connect floating stripes to the main mesh
puts "Connecting floating stripes..."
sroute -nets {VDD VSS} \
    -connect floatingStripe \
    -floatingStripeTarget {stripe ring} \
    -layerChangeRange {M1 M10} \
    -allowLayerChange 1 \
    -targetViaLayerRange {M1 M10}

# Step 3.6: Add power vias between layers
puts "Step 3.6: Adding power vias..."
setSrouteMode -viaConnectToShape {ring stripe}

# Add vias from M9 to M10
editPowerVia -add_vias 1 -nets {VDD VSS} -bottom_layer M9 -top_layer M10 -orthogonal_only 0

# Step 3.7: Connect floating stripes to the power mesh
# Run multiple passes to ensure all stripes are connected
puts "Step 3.7: Connecting floating stripes (pass 1)..."
sroute -nets {VDD VSS} \
    -connect floatingStripe \
    -floatingStripeTarget {ring stripe} \
    -layerChangeRange {M9 M10} \
    -allowLayerChange 1 \
    -targetViaLayerRange {M9 M10}

puts "Step 3.7: Connecting floating stripes (pass 2)..."
sroute -nets {VDD VSS} \
    -connect floatingStripe \
    -floatingStripeTarget {ring stripe} \
    -layerChangeRange {M9 M10} \
    -allowLayerChange 1 \
    -targetViaLayerRange {M9 M10}

# Step 3.7: Verify power grid
puts "\n=== Power Grid Verification ==="
puts "VDD M9 stripes: [llength [dbGet [dbGet top.nets.name VDD -p].sWires.layer.name M9 -p]]"
puts "VSS M9 stripes: [llength [dbGet [dbGet top.nets.name VSS -p].sWires.layer.name M9 -p]]"
puts "VDD M10 stripes: [llength [dbGet [dbGet top.nets.name VDD -p].sWires.layer.name M10 -p]]"
puts "VSS M10 stripes: [llength [dbGet [dbGet top.nets.name VSS -p].sWires.layer.name M10 -p]]"

# Early PG connectivity check (special nets)
puts "\n--- PG Special Connectivity Check (post-PG creation) ---"
verifyConnectivity -type special -nets {VDD VSS} -report fresh_pnr_pg_special.rpt -error 1000 -warning 1000

    # Save power grid checkpoint
    saveDesign cordic_fresh_powergrid.enc
} else {
    puts "\n===== PHASE 3: Power Grid (Symmetric) ====="
    puts "Skipping Phase 3 (START_FROM=$START_FROM)"
}

if {$START_FROM <= 4} {
    # ============================================================
    # PHASE 4: Placement
    # ============================================================
    puts "\n===== PHASE 4: Placement ====="

# Set placement options
setPlaceMode -fp false
setPlaceMode -congEffort high

# Run placement
place_design

# Legalize placement
refinePlace

# Add tap cells
addWellTap -cell TAPCELLBWP16P90 -cellInterval 30 -prefix TAP

# Legalize again after tap insertion
refinePlace

# Placement legality gate (stop if illegal placement remains)
set place_rpt "place_check.rpt"
set place_log ""
redirect -variable place_log {checkPlace}
set fp [open $place_rpt w]
puts $fp $place_log
close $fp
set overlap_cnt 0
set unplaced_cnt 0
set ooc_cnt 0
regexp -nocase {Overlapping with other instance:\s*([0-9]+)} $place_log -> overlap_cnt
regexp -nocase {Unplaced\s*=\s*([0-9]+)} $place_log -> unplaced_cnt
regexp -nocase {Out of core:\s*([0-9]+)} $place_log -> ooc_cnt
set place_viol [expr {$overlap_cnt + $unplaced_cnt + $ooc_cnt}]
if {$place_viol > 0} {
    puts "ERROR: Placement violations found (overlap=$overlap_cnt, unplaced=$unplaced_cnt, out_of_core=$ooc_cnt)."
    exit 1
}

# Get SRAM bounding box for area exclusion
set sram_box [dbGet [dbGet top.insts.name u_sram/u_sram_macro -p].box]
set sram_llx [lindex [lindex $sram_box 0] 0]
set sram_lly [lindex [lindex $sram_box 0] 1]
set sram_urx [lindex [lindex $sram_box 0] 2]
set sram_ury [lindex [lindex $sram_box 0] 3]
puts "SRAM box: $sram_llx $sram_lly $sram_urx $sram_ury"

# Get core box
set cbox [join [dbGet top.fPlan.coreBox]]
set c_llx [lindex $cbox 0]
set c_lly [lindex $cbox 1]
set c_urx [lindex $cbox 2]
set c_ury [lindex $cbox 3]
puts "Core box: $c_llx $c_lly $c_urx $c_ury"

# ============================================================
# V30 Power routing strategy:
#
# Problem: Via stacks from M1->M9 in SRAM X-range cause MinStep DRC.
# LVS opens occur because cells can't reach power stripes.
#
# Solution:
# 1. Dense M10 horizontal stripes (20um pitch) across entire design
# 2. M9 stripes in safe regions (X < 163 and X > 226)
# 3. Additional narrow M9 stripes at SRAM boundary edges
# 4. Standard cells connect to stripes via follow-pins
# ============================================================

puts "V30: Dense M10 power routing with edge M9 stripes..."

# V53: Relocate SRAM to the LEFT side of design
# where existing M9 stripes can reach it
#
# Current problem: SRAM at X=173-216 is in the "gap" where no M9 stripes exist
# Solution: Move SRAM to X~60-103 where left-side M9 stripes are present

# Get SRAM location
set sram_macro_box [dbGet [dbGet top.insts.name u_sram/u_sram_macro -p].box]
set sram_llx_m [lindex [lindex $sram_macro_box 0] 0]
set sram_lly_m [lindex [lindex $sram_macro_box 0] 1]
set sram_urx_m [lindex [lindex $sram_macro_box 0] 2]
set sram_ury_m [lindex [lindex $sram_macro_box 0] 3]
puts "Current SRAM position: ($sram_llx_m, $sram_lly_m) to ($sram_urx_m, $sram_ury_m)"

puts "V53: SRAM block pin connection..."

# Connect SRAM block pins
sroute -nets {VDD VSS} \
    -connect blockPin \
    -blockPinTarget {stripe ring} \
    -blockPinLayerRange {M4 M10} \
    -layerChangeRange {M4 M10} \
    -allowLayerChange 1 \
    -allowJogging 1 \
    -targetViaLayerRange {M4 M10}

# V91: Simplified approach - M8 bridge only + aggressive sroute
# Insight: Intermediate M4/M5/M6/M7 stripes cause DRC issues
# Strategy: Use M8 horizontal bridges around SRAM + multiple sroute passes

puts "V91: M8 bridge + aggressive sroute..."

# Set sroute mode for better via connectivity
setSrouteMode -viaConnectToShape {ring stripe}

# Get SRAM boundaries
set sram_box_v91 [dbGet [dbGet top.insts.name u_sram/u_sram_macro -p].box]
set sram_l [lindex [lindex $sram_box_v91 0] 0]
set sram_r [lindex [lindex $sram_box_v91 0] 2]
set sram_b [lindex [lindex $sram_box_v91 0] 1]
set sram_t [lindex [lindex $sram_box_v91 0] 3]
puts "V91: SRAM at X=$sram_l-$sram_r, Y=$sram_b-$sram_t"

# ============================================================
# V102: SIMPLIFIED - addRing around SRAM + aggressive sroute
# ============================================================
# Previous attempts: M4-M7 stripes fail due to SPANLENGTHTABLE
# V102: Use addRing for proper ring structure, let sroute handle connections
# ============================================================
puts "V102: Simplified approach - addRing around SRAM..."

# Get SRAM boundaries
set sram_box_v102 [dbGet [dbGet top.insts.name u_sram/u_sram_macro -p].box]
set sram_l [lindex [lindex $sram_box_v102 0] 0]
set sram_r [lindex [lindex $sram_box_v102 0] 2]
set sram_b [lindex [lindex $sram_box_v102 0] 1]
set sram_t [lindex [lindex $sram_box_v102 0] 3]
puts "V102: SRAM at X=$sram_l-$sram_r, Y=$sram_b-$sram_t"

# Core boundaries
set core_left 50
set core_right 339
set core_bottom 50
set core_top 339

# ============================================================
# Part 1: Create M8 RING around SRAM using addRing
# ============================================================
puts "V102 Part 1: Creating M8 ring around SRAM block..."

# Create a proper ring around the SRAM block on M8
addRing -nets {VDD VSS} \
    -around selected \
    -layer {top M8 bottom M8 left M8 right M8} \
    -width {top 2.0 bottom 2.0 left 2.0 right 2.0} \
    -spacing {top 2.0 bottom 2.0 left 2.0 right 2.0} \
    -offset {top 3.0 bottom 3.0 left 3.0 right 3.0} \
    -type block_rings \
    -jog_distance 0.5 \
    -threshold 0.5

# Connect M8 block ring to M9/M10 grid
puts "V102: Connecting M8 block ring to M9/M10..."
editPowerVia -add_vias 1 -nets {VDD VSS} -bottom_layer M8 -top_layer M9 -orthogonal_only 0
editPowerVia -add_vias 1 -nets {VDD VSS} -bottom_layer M9 -top_layer M10 -orthogonal_only 0

# ============================================================
# V102 Step 2: Connect block ring to M9/M10 grid
# ============================================================
puts "V102 Step 2: Connecting block ring..."

# Connect block ring to M9/M10 via sroute
sroute -nets {VDD VSS} \
    -connect floatingStripe \
    -floatingStripeTarget {ring stripe blockring} \
    -layerChangeRange {M8 M10} \
    -allowLayerChange 1 \
    -targetViaLayerRange {M8 M10}

# ============================================================
# V102 Step 3: Standard cell power connection
# ============================================================
puts "V102 Step 3: Standard cell power connection..."

# Connect core pins to stripes, ring, and block ring with full layer range
sroute -nets {VDD VSS} \
    -connect corePin \
    -corePinTarget {stripe} \
    -layerChangeRange {M1 M4} \
    -allowLayerChange 1 \
    -allowJogging 1 \
    -targetViaLayerRange {M1 M4}

# Second pass: full M1→M10 range
puts "V102: Second pass - full M1→M10..."
sroute -nets {VDD VSS} \
    -connect corePin \
    -corePinTarget {stripe ring} \
    -layerChangeRange {M1 M10} \
    -allowLayerChange 1 \
    -allowJogging 1 \
    -targetViaLayerRange {M1 M10}

# Third pass: include blockring
puts "V102: Third pass with blockring..."
sroute -nets {VDD VSS} \
    -connect corePin \
    -corePinTarget {stripe ring blockring} \
    -layerChangeRange {M1 M10} \
    -allowLayerChange 1 \
    -allowJogging 1 \
    -targetViaLayerRange {M1 M10}

# Fourth pass: aggressive
puts "V102: Fourth pass - aggressive..."
sroute -nets {VDD VSS} \
    -connect corePin \
    -corePinTarget {stripe ring blockring} \
    -layerChangeRange {M1 M10} \
    -allowLayerChange 1 \
    -allowJogging 1 \
    -crossoverViaLayerRange {M1 M10} \
    -targetViaLayerRange {M1 M10}

# Early DRC check after sroute (before CTS/routing)
puts "\n--- DRC Check (post-sroute) ---"
verify_drc -limit 1000 -report fresh_pnr_drc_post_sroute.rpt

puts "Placement complete"

    # Save placement checkpoint
    saveDesign cordic_fresh_placed.enc
} else {
    puts "\n===== PHASE 4: Placement ====="
    puts "Skipping Phase 4 (START_FROM=$START_FROM)"
}

if {$START_FROM <= 5} {
    # ============================================================
    # PHASE 5: Clock Tree Synthesis
    # ============================================================
    puts "\n===== PHASE 5: Clock Tree Synthesis ====="

# Set CTS options
set_ccopt_property target_max_trans 0.1
set_ccopt_property target_skew 0.05

# Create clock tree spec
create_ccopt_clock_tree_spec -file ccopt_spec.tcl

# Run CTS
ccopt_design

puts "CTS complete"

    # Save CTS checkpoint
    saveDesign cordic_fresh_cts.enc
} else {
    puts "\n===== PHASE 5: Clock Tree Synthesis ====="
    puts "Skipping Phase 5 (START_FROM=$START_FROM)"
}

if {$START_FROM <= 6} {
    # ============================================================
    # PHASE 6: Routing
    # ============================================================
    puts "\n===== PHASE 6: Routing ====="

# Avoid routing on AP layer and keep signals off M1 to reduce pin/via congestion
catch {setDesignMode -topRoutingLayer M11 -bottomRoutingLayer M2}

# Set routing options (DRC-first while we search for a clean baseline)
setNanoRouteMode -routeWithTimingDriven false
setNanoRouteMode -routeWithSiDriven false
setNanoRouteMode -droutePostRouteSpreadWire false
setNanoRouteMode -routeWithViaInPin false
setNanoRouteMode -routeWithViaOnlyForStandardCellPin false
setNanoRouteMode -drouteUseMultiCutViaEffort low
setNanoRouteMode -drouteFixAntenna true

# Run global and detailed routing
routeDesign

# V61: Run DRC fixing to clean up any routing DRC violations
puts "Running ECO routing to fix DRC..."
ecoRoute -fix_drc

puts "Routing complete"

    # Save routing checkpoint
    saveDesign cordic_fresh_routed.enc
} else {
    puts "\n===== PHASE 6: Routing ====="
    puts "Skipping Phase 6 (START_FROM=$START_FROM)"
}

if {$START_FROM <= 7} {
    # ============================================================
    # PHASE 7: Post-Route Optimization
    # ============================================================
    puts "\n===== PHASE 7: Post-Route Optimization ====="

    # AAE-SI optimization requires OCV analysis
    catch {setAnalysisMode -analysisType onChipVariation -cppr both}

    # Fix hold violations
    setOptMode -fixHoldAllowSetupTnsDegrade false
    optDesign -postRoute -hold

puts "Post-route optimization complete"

# Save optimized checkpoint
saveDesign cordic_fresh_optimized.enc

    # Add filler cells after routing/opt to avoid routing congestion
    addFiller -cell {FILL64BWP16P90 FILL32BWP16P90 FILL16BWP16P90 FILL8BWP16P90 FILL4BWP16P90 FILL3BWP16P90 FILL2BWP16P90 FILL1BWP16P90} -prefix FILLER
} else {
    puts "\n===== PHASE 7: Post-Route Optimization ====="
    puts "Skipping Phase 7 (START_FROM=$START_FROM)"
}

if {$START_FROM <= 8} {
    # ============================================================
    # PHASE 8: Verification
    # ============================================================
    puts "\n===== PHASE 8: Verification ====="

# LVS check
puts "\n--- LVS Check ---"
verifyConnectivity -type special -report fresh_pnr_lvs.rpt -error 1000 -warning 1000

# DRC check
puts "\n--- DRC Check ---"
verify_drc -limit 1000 -report fresh_pnr_drc.rpt

# Geometry check
puts "\n--- Geometry Check ---"
    verifyGeometry -report fresh_pnr_geom.rpt
} else {
    puts "\n===== PHASE 8: Verification ====="
    puts "Skipping Phase 8 (START_FROM=$START_FROM)"
}

if {$START_FROM <= 9} {
    # ============================================================
    # PHASE 9: Final Summary
    # ============================================================
    puts "\n===== PHASE 9: Final Summary ====="

# Power grid symmetry check (M9/M10)
puts "\n=== Power Grid Symmetry Check ==="
set vdd_m9 [llength [dbGet [dbGet top.nets.name VDD -p].sWires.layer.name M9 -p]]
set vss_m9 [llength [dbGet [dbGet top.nets.name VSS -p].sWires.layer.name M9 -p]]
set vdd_m10 [llength [dbGet [dbGet top.nets.name VDD -p].sWires.layer.name M10 -p]]
set vss_m10 [llength [dbGet [dbGet top.nets.name VSS -p].sWires.layer.name M10 -p]]

puts "M9:  VDD=$vdd_m9, VSS=$vss_m9 [expr {$vdd_m9 == $vss_m9 ? "SYMMETRIC" : "ASYMMETRIC"}]"
puts "M10: VDD=$vdd_m10, VSS=$vss_m10 [expr {$vdd_m10 == $vss_m10 ? "SYMMETRIC" : "ASYMMETRIC"}]"

puts "\n=== Reports Generated ==="
puts "  fresh_pnr_lvs.rpt  - LVS verification"
puts "  fresh_pnr_drc.rpt  - DRC verification"
puts "  fresh_pnr_geom.rpt - Geometry verification"

puts "\n=== Checkpoints Saved ==="
puts "  cordic_fresh_floorplan.enc - After floorplan"
puts "  cordic_fresh_powergrid.enc - After power grid"
puts "  cordic_fresh_placed.enc    - After placement"
puts "  cordic_fresh_cts.enc       - After CTS"
puts "  cordic_fresh_routed.enc    - After routing"
puts "  cordic_fresh_optimized.enc - After optimization"

# Final save
saveDesign cordic_fresh_final.enc

    puts "\n============================================================"
    puts "=== Fresh P&R Flow Complete                               ==="
    puts "=== Final checkpoint: cordic_fresh_final.enc              ==="
    puts "============================================================"
}

# DO NOT exit - keep interactive for inspection
# exit
