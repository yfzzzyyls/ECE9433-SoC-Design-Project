##########################################################################################
# User-defined variables for logical library setup in dc_setup.tcl
##########################################################################################

set PDK_DIR                  "/ip/tsmc/tsmc16adfp/stdcell"
set SRAM_DIR                 "/ip/tsmc/tsmc16adfp/sram"

#set ADDITIONAL_SEARCH_PATH   "$PDK_DIR/NLDM $PDK_DIR/NDM ./rtl ./scripts"
set ADDITIONAL_SEARCH_PATH   "$env(SYN_HOME)/libraries/syn $env(SYN_HOME)/dw/syn_ver $env(SYN_HOME)/dw/sim_ver $PDK_DIR/NLDM $PDK_DIR/NDM $SRAM_DIR/NLDM $SRAM_DIR/VERILOG ./rtl ./scripts"

set TARGET_LIBRARY_FILES     "N16ADFP_StdCelltt0p8v25c.db N16ADFP_SRAM_tt0p8v0p8v25c_100a.db"                              ;#  Logic cell library files

##########################################################################################
# User-defined variables for physical library setup in dc_setup.tcl
##########################################################################################

set NDM_DESIGN_LIB           "TOP.dlib"                 ;#  User-defined NDM design library name

set NDM_REFERENCE_LIBS       "N16ADFP_StdCell_physicalonly.ndm"                 ;#  NDM physical cell libraries

# set TECH_FILE                ""              ;#  Technology file

# set TLUPLUS_MAX_FILE         "saed32nm_1p9m_Cmax.tluplus"    ;#  Max TLUPlus file

# set MAP_FILE                 "saed32nm_tf_itf_tluplus.map"   ;#  Mapping file for TLUplus

return
