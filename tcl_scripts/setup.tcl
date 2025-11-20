source rm_setup/dc_setup.tcl

set_app_var alib_library_analysis_path ../  ;# Common ALIB library location
define_design_lib WORK -path ./work         ;# Location of "analyze"d files

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#  Verify Settings
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "\n=================================================================="
echo "\nLibrary Settings:"
echo "search_path:              $search_path"
echo "link_library:             $link_library"
echo "target_library:           $target_library"
echo "physical libraries:       $NDM_REFERENCE_LIBS"
echo "physical design library:  $NDM_DESIGN_LIB"
echo "\n=================================================================="
