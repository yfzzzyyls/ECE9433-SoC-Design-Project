##########################################################################################
# User-defined variables for logical library setup in dc_setup.tcl
##########################################################################################

set ADDITIONAL_SEARCH_PATH   "../ref/DBs ../ref/CLIBs ../ref/tech ./rtl ./scripts"  ;#  Directories containing logic libraries,
                                                                                     #  logic design and script files.

set TARGET_LIBRARY_FILES     "saed32lvt_ss0p75v125c.db"                             ;#  Logic cell library files

##########################################################################################
# User-defined variables for physical library setup in dc_setup.tcl
##########################################################################################

set NDM_DESIGN_LIB           "TOP.dlib"                      ;#  User-defined NDM design library name

set NDM_REFERENCE_LIBS       "saed32_lvt.ndm"                ;#  NDM physical cell libraries

set TECH_FILE                "saed32nm_1p9m.tf"              ;#  Technology file

set TLUPLUS_MAX_FILE         "saed32nm_1p9m_Cmax.tluplus"    ;#  Max TLUPlus file

set MAP_FILE                 "saed32nm_tf_itf_tluplus.map"   ;#  Mapping file for TLUplus

return

