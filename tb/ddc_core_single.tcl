## Utility
source ./util.tcl

## Device setting (KCU105)
set p_device "xcku040-ffva1156-2-e"
set p_board "xilinx.com:kcu105:part0:1.5"

set project_name "ddc_core_single"

create_project -force $project_name ./${project_name} -part $p_device
set_property board_part $p_board [current_project]

add_files -norecurse "./ddc_core.v"

### DDS
create_ip -vlnv [latest_ip dds_compiler] -module_name dds
set_property CONFIG.Parameter_Entry "Hardware_Parameters" [get_ips dds]
set_property CONFIG.PINC1 0 [get_ips dds]
set_property CONFIG.DDS_Clock_Rate 250 [get_ips dds]
set_property CONFIG.Mode_of_Operation "Standard" [get_ips dds]
set_property CONFIG.Phase_Increment "Programmable" [get_ips dds]
set_property CONFIG.Phase_offset "Programmable" [get_ips dds]
set_property CONFIG.Phase_Width 20 [get_ips dds]
set_property CONFIG.Output_Width 14 [get_ips dds]
set_property CONFIG.Noise_Shaping "None" [get_ips dds]

### DDC
#### Multiplier
create_ip -vlnv [latest_ip mult_gen] -module_name multiplier
set_property CONFIG.PortAWidth 14 [get_ips multiplier]
set_property CONFIG.PortBWidth 14 [get_ips multiplier]
set_property CONFIG.Multiplier_Construction "Use_Mults" [get_ips multiplier]
set_property CONFIG.OptGoal "Area" [get_ips multiplier]
set_property CONFIG.OutputWidthHigh 29 [get_ips multiplier]
set_property CONFIG.PipeStages 3 [get_ips multiplier]
set_property generate_synth_checkpoint 0 [get_files multiplier.xci]

#### Adder
create_ip -vlnv [latest_ip c_addsub] -module_name adder
set_property CONFIG.A_Width 28 [get_ips adder]
set_property CONFIG.B_Width 28 [get_ips adder]
set_property CONFIG.Out_Width 29 [get_ips adder]
set_property CONFIG.CE "false" [get_ips adder]
set_property CONFIG.Latency 3 [get_ips adder]
set_property generate_synth_checkpoint 0 [get_files adder.xci]

#### Subtracter
create_ip -vlnv [latest_ip c_addsub] -module_name subtracter
set_property CONFIG.Add_Mode "Subtract" [get_ips subtracter]
set_property CONFIG.A_Width 28 [get_ips subtracter]
set_property CONFIG.B_Width 28 [get_ips subtracter]
set_property CONFIG.Out_Width 29 [get_ips subtracter]
set_property CONFIG.CE "false" [get_ips subtracter]
set_property CONFIG.Latency 3 [get_ips subtracter]
set_property generate_synth_checkpoint 0 [get_files subtracter.xci]

set_property top ddc_core [current_fileset]

### Simulation
add_files -fileset sim_1 -norecurse ./sim_ddc_core.sv
set_property top sim_ddc_core [get_filesets sim_1]
generate_target Simulation [get_files dds.xci]
generate_target Simulation [get_files subtracter.xci]
generate_target Simulation [get_files adder.xci]
generate_target Simulation [get_files multiplier.xci]

# Run
## Synthesis
#launch_runs synth_1
#wait_on_run synth_1
#open_run synth_1
#report_utilization -file "./utilization_synth.txt"

## Implementation
#set_property strategy Performance_Retiming [get_runs impl_1]
#launch_runs impl_1 -to_step write_bitstream
#wait_on_run impl_1
#open_run impl_1
#report_timing_summary -file timing_impl.log
#report_utilization -file "./utilization_impl.txt"
