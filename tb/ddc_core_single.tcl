## Utility
source ../util.tcl

## Device setting (KCU105)
set p_device "xcku040-ffva1156-2-e"
set p_board "xilinx.com:kcu105:part0:1.7"
set project_name "ddc_core_single"

create_project -force $project_name ./${project_name} -part $p_device
set_property board_part $p_board [current_project]

add_files -norecurse "../hdl/ddc_core.v"

### DDS
################################################ Parameters
set f_clk_MHz 256
set dds_phase_width 32
set dds_out_width 14
set adc_width 12
set mult_out_width 26
set adder_out_width 27
set adder_1st_width 28
set adder_2nd_width 29
set adder_3rd_width 30
set adder_dds_width 16

################################################ IP generation
### DDS
create_ip -vlnv [latest_ip dds_compiler] -module_name dds_oct
set dds_oct [get_ips dds_oct]
set_property CONFIG.Parameter_Entry "Hardware_Parameters" $dds_oct
set_property CONFIG.PINC1 0 $dds_oct
set_property CONFIG.DDS_Clock_Rate $f_clk_MHz $dds_oct
set_property CONFIG.Mode_of_Operation "Standard" $dds_oct
set_property CONFIG.Phase_Increment "Streaming" $dds_oct
set_property CONFIG.Phase_offset "Streaming" $dds_oct
set_property CONFIG.Phase_Width $dds_phase_width $dds_oct
set_property CONFIG.Output_Width $dds_out_width $dds_oct
set_property CONFIG.Noise_Shaping "None" $dds_oct
set_property CONFIG.Resync {true} $dds_oct
set_property generate_synth_checkpoint 0 [get_files dds_oct.xci]

### DDC core
#### Multiplier
create_ip -vlnv [latest_ip mult_gen] -module_name multiplier_oct
set mult_oct [get_ips multiplier_oct]
set_property CONFIG.PortAWidth $adc_width $mult_oct
set_property CONFIG.PortBWidth $dds_out_width $mult_oct
set_property CONFIG.Multiplier_Construction "Use_Mults" $mult_oct
set_property CONFIG.OptGoal "Area" $mult_oct
set_property CONFIG.OutputWidthHigh $mult_out_width $mult_oct
set_property CONFIG.PipeStages 3 $mult_oct
set_property generate_synth_checkpoint 0 [get_files multiplier_oct.xci]

#### Adder
create_ip -vlnv [latest_ip c_addsub] -module_name adder_oct
set adder_oct [get_ips adder_oct]
set_property CONFIG.A_Width $mult_out_width $adder_oct
set_property CONFIG.B_Width $mult_out_width $adder_oct
set_property CONFIG.Out_Width $adder_out_width $adder_oct
set_property CONFIG.CE "false" $adder_oct
set_property CONFIG.Latency 3 $adder_oct
set_property generate_synth_checkpoint 0 [get_files adder_oct.xci]

#### Subtractor
create_ip -vlnv [latest_ip c_addsub] -module_name subtractor_oct
set subtractor_oct [get_ips subtractor_oct]
set_property CONFIG.Add_Mode "Subtract" $subtractor_oct
set_property CONFIG.A_Width $mult_out_width $subtractor_oct
set_property CONFIG.B_Width $mult_out_width $subtractor_oct
set_property CONFIG.Out_Width $adder_out_width $subtractor_oct
set_property CONFIG.CE "false" $subtractor_oct
set_property CONFIG.Latency 3 $subtractor_oct
set_property generate_synth_checkpoint 0 [get_files subtractor_oct.xci]

set_property top ddc_core [current_fileset]

### Simulation
add_files -fileset sim_1 -norecurse ./sim_ddc_core.sv
set_property top sim_ddc_core [get_filesets sim_1]
generate_target Simulation [get_files dds_oct.xci]
generate_target Simulation [get_files subtracter_oct.xci]
generate_target Simulation [get_files adder_oct.xci]
generate_target Simulation [get_files multiplier_oct.xci]

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
