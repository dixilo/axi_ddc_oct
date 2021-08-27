## Utility
source ./util.tcl

## Device setting (KCU105)
set p_device "xcku040-ffva1156-2-e"
set p_board "xilinx.com:kcu105:part0:1.5"

set project_name "accumulator"

create_project -force $project_name ./${project_name} -part $p_device
set_property board_part $p_board [current_project]

add_files -norecurse "./accumulator.v"

### Accumulator
create_ip -vlnv [latest_ip c_accum] -module_name c_accum
set_property CONFIG.Implementation {DSP48} [get_ips c_accum]
set_property CONFIG.Input_Width {31} [get_ips c_accum]
set_property CONFIG.Output_Width {48} [get_ips c_accum]
set_property CONFIG.Latency_Configuration {Manual} [get_ips c_accum]
set_property CONFIG.Latency {2} [get_ips c_accum]
set_property CONFIG.SCLR {false} [get_ips c_accum]
set_property CONFIG.Bypass {true} [get_ips c_accum]

set_property top accumulator [current_fileset]

### Simulation
add_files -fileset sim_1 -norecurse ./sim_accum.sv
set_property top sim_accum [get_filesets sim_1]
generate_target Simulation [get_files c_accum.xci]

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
