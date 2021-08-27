open_project ./ddc_core_single/ddc_core_single.xpr

add_files -fileset sim_1 -norecurse ./sim_ddc_mult.sv
set_property top sim_ddc_mult [get_filesets sim_1]

launch_simulation
run all
