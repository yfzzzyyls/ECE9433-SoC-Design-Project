# MMMC setup for Innovus import (v21.x syntax)
# Timing libraries (typ corner)
set std_lib   "/ip/tsmc/tsmc16adfp/stdcell/NLDM/N16ADFP_StdCelltt0p8v25c.lib"
set sram_lib  "/ip/tsmc/tsmc16adfp/sram/NLDM/N16ADFP_SRAM_tt0p8v0p8v25c_100a.lib"

# SDC constraints
set sdc_file  [file join [file dirname [file normalize [info script]]] soc_top.sdc]

# Create the library set (specify timing libs directly)
create_library_set  -name libset_typ   -timing [list $std_lib $sram_lib]

# Create timing condition (required for v21.x delay corner syntax)
create_timing_condition -name tc_typ -library_set libset_typ

# Create RC corner and delay corner
create_rc_corner    -name rc_typ
create_delay_corner -name dc_typ -timing_condition tc_typ -rc_corner rc_typ

# Create constraint mode and analysis view
create_constraint_mode -name mode_func -sdc_files [list $sdc_file]
create_analysis_view   -name view_typ  -constraint_mode mode_func -delay_corner dc_typ
set_analysis_view      -setup {view_typ} -hold {view_typ}
