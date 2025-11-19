# This file has been edited to keep it simple

printvar target_library
printvar link_library
alias
check_library
check_tlu_plus_files

analyze -format verilog ./rtl/TOP.v
elaborate TOP
link

write_file -hierarchy -f ddc -out unmapped/TOP.ddc
list_designs
list_libs

set_preferred_routing_direction -layers {M1 M3 M5 M7 M9} -direction horizontal
set_preferred_routing_direction -layers {M2 M4 M6 M8 MRDL} -direction vertical
source -verbose TOP.con

compile_ultra

report_constraint -all
report_timing
report_area

write_file -hierarchy -format ddc -output ./mapped/TOP.ddc
write_icc2_files -force -output ./mapped/TOP_icc2

remove_design -all
