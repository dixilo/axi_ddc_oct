## Utility
source ./util.tcl

## Device setting (KCU105)
set p_device "xcku040-ffva1156-2-e"
set p_board "xilinx.com:kcu105:part0:1.5"

set project_name "axi_bench"

create_project -force $project_name ./${project_name} -part $p_device
set_property board_part $p_board [current_project]

set_property  ip_repo_paths  "./test_ip" [current_project]

## create board design
create_bd_design "system"

### DDC_DAQ2
create_bd_cell -type ip -vlnv [latest_ip axi_ddc_daq2] axi_ddc_daq2

### AXI VIP
create_bd_cell -type ip -vlnv [latest_ip axi_vip] axi_vip
set_property CONFIG.INTERFACE_MODE {MASTER} [get_bd_cells axi_vip]

### Interconnect
create_bd_cell -type ip -vlnv [latest_ip axi_interconnect] axi_interconnect
set_property CONFIG.NUM_MI {1} [get_bd_cells axi_interconnect]

### XFFT (test)
create_bd_cell -type ip -vlnv [latest_ip xfft] xfft_0
set_property -dict [list CONFIG.target_data_throughput {250} CONFIG.input_width {14} CONFIG.scaling_options {unscaled} CONFIG.rounding_modes {convergent_rounding} CONFIG.xk_index {true} CONFIG.number_of_stages_using_block_ram_for_data_and_phase_factors {3}] [get_bd_cells xfft_0]


## Connection
### Port definition
#### Clock and reset
create_bd_port -dir I -type clk axi_clk
set_property CONFIG.FREQ_HZ 50000000 [get_bd_ports axi_clk]
create_bd_port -dir I -type clk dev_clk
set_property CONFIG.FREQ_HZ 250000000 [get_bd_ports dev_clk]

create_bd_port -dir I -type rst axi_aresetn
create_bd_port -dir I -type rst dev_rst
set_property CONFIG.POLARITY ACTIVE_HIGH [get_bd_ports dev_rst]

#### Data
create_bd_port -dir I -from 31 -to 0 -type data data_in_0
create_bd_port -dir I -from 31 -to 0 -type data data_in_1
create_bd_port -dir I -from 31 -to 0 -type data data_in_2
create_bd_port -dir I -from 31 -to 0 -type data data_in_3
create_bd_port -dir I resync

create_bd_port -dir O -from 95 -to 0 -type data data_out
create_bd_port -dir O valid_out


### AXI intf
connect_bd_intf_net [get_bd_intf_pins axi_vip/M_AXI] -boundary_type upper [get_bd_intf_pins axi_interconnect/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_ddc_daq2/s00_axi] -boundary_type upper [get_bd_intf_pins axi_interconnect/M00_AXI]

### AXI Clock
connect_bd_net [get_bd_ports axi_clk] [get_bd_pins axi_vip/aclk]
connect_bd_net [get_bd_ports axi_clk] [get_bd_pins axi_interconnect/ACLK]
connect_bd_net [get_bd_ports axi_clk] [get_bd_pins axi_interconnect/S00_ACLK]
connect_bd_net [get_bd_ports axi_clk] [get_bd_pins axi_interconnect/M00_ACLK]
connect_bd_net [get_bd_ports axi_clk] [get_bd_pins axi_ddc_daq2/s00_axi_aclk]

### Device clk
connect_bd_net [get_bd_ports dev_clk] [get_bd_pins axi_ddc_daq2/dev_clk]

### AXI aresetn
connect_bd_net [get_bd_ports axi_aresetn] [get_bd_pins axi_vip/aresetn]
connect_bd_net [get_bd_ports axi_aresetn] [get_bd_pins axi_interconnect/ARESETN]
connect_bd_net [get_bd_ports axi_aresetn] [get_bd_pins axi_interconnect/M00_ARESETN]
connect_bd_net [get_bd_ports axi_aresetn] [get_bd_pins axi_interconnect/S00_ARESETN]
connect_bd_net [get_bd_ports axi_aresetn] [get_bd_pins axi_ddc_daq2/s00_axi_aresetn]

### dev rst
connect_bd_net [get_bd_ports dev_rst] [get_bd_pins axi_ddc_daq2/dev_rst]

### Data
connect_bd_net [get_bd_ports data_in_0] [get_bd_pins axi_ddc_daq2/data_in_0]
connect_bd_net [get_bd_ports data_in_1] [get_bd_pins axi_ddc_daq2/data_in_1]
connect_bd_net [get_bd_ports data_in_2] [get_bd_pins axi_ddc_daq2/data_in_2]
connect_bd_net [get_bd_ports data_in_3] [get_bd_pins axi_ddc_daq2/data_in_3]

connect_bd_net [get_bd_ports data_out] [get_bd_pins axi_ddc_daq2/data_out]
connect_bd_net [get_bd_ports valid_out] [get_bd_pins axi_ddc_daq2/valid_out]
connect_bd_net [get_bd_ports resync] [get_bd_pins axi_ddc_daq2/resync]

### FFT (test)
connect_bd_net [get_bd_ports dev_clk] [get_bd_pins xfft_0/aclk]
make_bd_intf_pins_external  [get_bd_intf_pins xfft_0/S_AXIS_CONFIG]
make_bd_intf_pins_external  [get_bd_intf_pins xfft_0/S_AXIS_DATA]
make_bd_intf_pins_external  [get_bd_intf_pins xfft_0/M_AXIS_DATA]


## Project
save_bd_design
validate_bd_design

set project_system_dir "./${project_name}/${project_name}.srcs/sources_1/bd/system"

set_property synth_checkpoint_mode None [get_files  $project_system_dir/system.bd]
generate_target {synthesis implementation} [get_files  $project_system_dir/system.bd]
make_wrapper -files [get_files $project_system_dir/system.bd] -top

import_files -force -norecurse -fileset sources_1 $project_system_dir/hdl/system_wrapper.v
#add_files -norecurse -fileset sources_1 [glob ./src/*]
set_property top system_wrapper [current_fileset]

### Simulation
add_files -fileset sim_1 -norecurse ./sim_full.sv
set_property top sim_full [get_filesets sim_1]


# Run
## Synthesis
#launch_runs synth_1
#wait_on_run synth_1
#open_run synth_1
#report_utilization -file "./utilization.txt" -name utilization_1

## Implementation
#set_property strategy Performance_Retiming [get_runs impl_1]
#launch_runs impl_1 -to_step write_bitstream
#wait_on_run impl_1
#open_run impl_1
#report_timing_summary -file timing_impl.log
