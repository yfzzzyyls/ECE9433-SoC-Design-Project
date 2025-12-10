source rm_setup/common_setup.tcl

######################################################################
# Logical Library Settings
######################################################################
#set_app_var search_path    "$search_path $ADDITIONAL_SEARCH_PATH"
set_app_var search_path    "$ADDITIONAL_SEARCH_PATH"
set_app_var target_library  $TARGET_LIBRARY_FILES
set_app_var link_library   "* $target_library"

######################################################################
# Physical Library Settings
######################################################################

if {![file isdirectory $NDM_DESIGN_LIB]} {
  create_lib \
    -ref_libs   $NDM_REFERENCE_LIBS \
    $NDM_DESIGN_LIB
}

# Only available in topo; guard for non-topo runs.
if {[info commands open_lib] != ""} {
  open_lib $NDM_DESIGN_LIB
}


# set_tlu_plus_files \
#     -max_tluplus  $TLUPLUS_MAX_FILE \
#     -tech2itf_map $MAP_FILE
