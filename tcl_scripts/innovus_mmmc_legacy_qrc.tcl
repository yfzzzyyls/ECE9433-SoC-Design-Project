# Legacy MMMC setup with QRC Tech Files - Industry Standard Flow
# Timing libraries (typ corner)
set std_lib   "/ip/tsmc/tsmc16adfp/stdcell/NLDM/N16ADFP_StdCelltt0p8v25c.lib"
set sram_lib  "/ip/tsmc/tsmc16adfp/sram/NLDM/N16ADFP_SRAM_tt0p8v0p8v25c_100a.lib"

# QRC Technology File - using worst corner for typical analysis
set qrc_tech  "/ip/tsmc/tsmc16adfp/tech/RC/N16ADFP_QRC/worst/qrcTechFile"

# SDC constraints - absolute path
set sdc_file "/home/fy2243/ECE9433-SoC-Design-Project/tcl_scripts/soc_top.sdc"

# Create library set
create_library_set -name libset_typ -timing [list $std_lib $sram_lib]

# Create RC corner with QRC tech file (correct option for Quantus QRC)
# Use -qx_tech_file for Quantus QRC technology files
create_rc_corner -name rc_typ \
                 -qx_tech_file $qrc_tech \
                 -temperature 25

# Create delay corner (legacy syntax)
create_delay_corner -name dc_typ -library_set libset_typ -rc_corner rc_typ

# Create constraint mode and analysis view
create_constraint_mode -name mode_func -sdc_files [list $sdc_file]
create_analysis_view -name view_typ -constraint_mode mode_func -delay_corner dc_typ
set_analysis_view -setup {view_typ} -hold {view_typ}

puts ""
puts "=========================================="
puts "MMMC Setup with QRC Tech Files (Legacy)"
puts "=========================================="
puts "QRC Tech: $qrc_tech"
puts "Temperature: 25C"
puts "=========================================="
puts ""
