# FFT quad
set ip_name "axi_ddc_oct"
create_project $ip_name "." -force
source ./util.tcl

# file
set proj_fileset [get_filesets sources_1]
add_files -norecurse -scan_for_includes -fileset $proj_fileset [list \
"src/axi_ddc_oct.v" \
"src/axi_ddc_oct_core.v" \
"src/accumulator.v" \
"src/ddc_core.v" \
"src/ddc_oct.v" \
]

set_property "top" "axi_ddc_oct" $proj_fileset

ipx::package_project -root_dir "." -vendor kuhep -library user -taxonomy /kuhep
set_property name $ip_name [ipx::current_core]
set_property vendor_display_name {kuhep} [ipx::current_core]

################################################ Parameters
set f_clk_MHz 256
set dds_phase_width 32
set dds_out_width 14
set adc_width 12
set mult_out_width 26
set adder_out_width 27


################################################ IP generation
############### DDC QUAD
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
set_property generate_synth_checkpoint 0 [get_files adder_oct.xci]

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
set_property generate_synth_checkpoint 0 [get_files adder_dd2.xci]

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

#### Adder for phase
create_ip -vlnv [latest_ip c_addsub] -module_name adder_phase_oct
set adder_phase_oct [get_ips adder_phase_oct]
set_property CONFIG.A_Width $dds_phase_width $adder_phase_oct
set_property CONFIG.B_Width $dds_phase_width $adder_phase_oct
set_property CONFIG.Out_Width $dds_phase_width $adder_phase_oct
set_property CONFIG.CE "false" $adder_phase_oct
set_property CONFIG.Latency 3 $adder_phase_oct
set_property generate_synth_checkpoint 0 [get_files adder_phase_oct.xci]

#### 1st stage adder
create_ip -vlnv [latest_ip c_addsub] -module_name adder_1st_oct
set_property CONFIG.A_Width 29 [get_ips adder_1st_dd2]
set_property CONFIG.B_Width 29 [get_ips adder_1st_dd2]
set_property CONFIG.Out_Width 30 [get_ips adder_1st_dd2]
set_property CONFIG.CE "false" [get_ips adder_1st_dd2]
set_property CONFIG.Latency 3 [get_ips adder_1st_dd2]
set_property generate_synth_checkpoint 0 [get_files adder_1st_dd2.xci]

#### 2nd stage adder
create_ip -vlnv [latest_ip c_addsub] -module_name adder_2nd_dd2
set_property CONFIG.A_Width 30 [get_ips adder_2nd_dd2]
set_property CONFIG.B_Width 30 [get_ips adder_2nd_dd2]
set_property CONFIG.Out_Width 31 [get_ips adder_2nd_dd2]
set_property CONFIG.CE "false" [get_ips adder_2nd_dd2]
set_property CONFIG.Latency 3 [get_ips adder_2nd_dd2]
set_property generate_synth_checkpoint 0 [get_files adder_2nd_dd2.xci]

############### Accumulator
### Accumulator
create_ip -vlnv [latest_ip c_accum] -module_name c_accum_dd2
set_property CONFIG.Implementation {DSP48} [get_ips c_accum_dd2]
set_property CONFIG.Input_Width {31} [get_ips c_accum_dd2]
set_property CONFIG.Output_Width {48} [get_ips c_accum_dd2]
set_property CONFIG.Latency_Configuration {Manual} [get_ips c_accum_dd2]
set_property CONFIG.Latency {2} [get_ips c_accum_dd2]
set_property CONFIG.SCLR {false} [get_ips c_accum_dd2]
set_property CONFIG.Bypass {true} [get_ips c_accum_dd2]
set_property generate_synth_checkpoint 0 [get_files c_accum_dd2.xci]

################################################ Register XCI files
# file groups
ipx::add_file ./axi_ddc_daq2.srcs/sources_1/ip/dds_dd2/dds_dd2.xci \
[ipx::get_file_groups xilinx_anylanguagesynthesis -of_objects [ipx::current_core]]
ipx::add_file ./axi_ddc_daq2.srcs/sources_1/ip/multiplier_dd2/multiplier_dd2.xci \
[ipx::get_file_groups xilinx_anylanguagesynthesis -of_objects [ipx::current_core]]
ipx::add_file ./axi_ddc_daq2.srcs/sources_1/ip/adder_dd2/adder_dd2.xci \
[ipx::get_file_groups xilinx_anylanguagesynthesis -of_objects [ipx::current_core]]
ipx::add_file ./axi_ddc_daq2.srcs/sources_1/ip/subtracter_dd2/subtracter_dd2.xci \
[ipx::get_file_groups xilinx_anylanguagesynthesis -of_objects [ipx::current_core]]
ipx::add_file ./axi_ddc_daq2.srcs/sources_1/ip/adder_phase_dd2/adder_phase_dd2.xci \
[ipx::get_file_groups xilinx_anylanguagesynthesis -of_objects [ipx::current_core]]
ipx::add_file ./axi_ddc_daq2.srcs/sources_1/ip/adder_1st_dd2/adder_1st_dd2.xci \
[ipx::get_file_groups xilinx_anylanguagesynthesis -of_objects [ipx::current_core]]
ipx::add_file ./axi_ddc_daq2.srcs/sources_1/ip/adder_2nd_dd2/adder_2nd_dd2.xci \
[ipx::get_file_groups xilinx_anylanguagesynthesis -of_objects [ipx::current_core]]
ipx::add_file ./axi_ddc_daq2.srcs/sources_1/ip/c_accum_dd2/c_accum_dd2.xci \
[ipx::get_file_groups xilinx_anylanguagesynthesis -of_objects [ipx::current_core]]

# Reordering
ipx::reorder_files -after ./axi_ddc_daq2.srcs/sources_1/ip/c_accum_dd2/c_accum_dd2.xci ../axi_ddc_daq2.v [ipx::get_file_groups xilinx_anylanguagesynthesis -of_objects [ipx::current_core]]
ipx::reorder_files -after ../ddc_quad.v ../axi_ddc_daq2_core.v [ipx::get_file_groups xilinx_anylanguagesynthesis -of_objects [ipx::current_core]]

# Interface
ipx::infer_bus_interface dev_clk xilinx.com:signal:clock_rtl:1.0 [ipx::current_core]
ipx::save_core [ipx::current_core]
