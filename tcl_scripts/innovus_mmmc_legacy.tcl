# Legacy MMMC setup for batch mode (old syntax)
# Timing libraries (typ corner)
set std_lib   "/ip/tsmc/tsmc16adfp/stdcell/NLDM/N16ADFP_StdCelltt0p8v25c.lib"
set sram_lib  "/ip/tsmc/tsmc16adfp/sram/NLDM/N16ADFP_SRAM_tt0p8v0p8v25c_100a.lib"

# SDC constraints
set sdc_file  [file join [file dirname [file normalize [info script]]] soc_top.sdc]

# Create library set
create_library_set -name libset_typ -timing [list $std_lib $sram_lib]

# Create RC and delay corners (legacy syntax)
create_rc_corner -name rc_typ
create_delay_corner -name dc_typ -library_set libset_typ -rc_corner rc_typ

# Create constraint mode and analysis view
create_constraint_mode -name mode_func -sdc_files [list $sdc_file]
create_analysis_view -name view_typ -constraint_mode mode_func -delay_corner dc_typ
set_analysis_view -setup {view_typ} -hold {view_typ}
