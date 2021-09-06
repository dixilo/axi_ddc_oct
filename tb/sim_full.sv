`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
import axi_vip_pkg::*;
import system_axi_vip_0_pkg::*;

module sim_full(

    );

    localparam STEP_SYS = 200;
    localparam STEP_DEV = 40;
    localparam SIM_LENGTH = 65536;
    localparam DS_RATE = 32;

    // input
    logic [127:0] s_axis_i_tdata;
    logic         s_axis_i_tready;
    logic         s_axis_i_valid;
    logic [127:0] s_axis_q_tdata;
    logic         s_axis_q_tready;
    logic         s_axis_q_valid;

    logic [63:0]  s_axis_phase_tdata;
    logic         s_axis_phase_tvalid;
    logic         resync;

    logic [127:0] m_axis_ddsi_tdata;
    logic         m_axis_ddsi_tvalid;
    logic         m_axis_ddsi_tready;

    logic [127:0] m_axis_ddsq_tdata;
    logic         m_axis_ddsq_tvalid;
    logic         m_axis_ddsq_tready;

    logic [63:0]  m_axis_ddc_tdata;
    logic         m_axis_ddc_tvalid;
    logic         m_axis_ddc_tready;

    wire [31:0] pinc = s_axis_phase_tdata[31:0];
    wire [31:0] poff = s_axis_phase_tdata[63:31];

    system_wrapper dut(.*);

    // Utility
    integer fd_din_i;
    integer fd_din_q;

    integer fd_dout;
    logic write_ready = 0;
    logic [$clog2(SIM_LENGTH)-1:0] counter = 0;
    logic finish = 0;

    // read setting
    integer fd_p;

    // data flow control
    logic din_on;
    logic din_fin;


    system_axi_vip_0_mst_t  vip_agent;


    task clk_gen();
        axi_clk = 0;
        forever #(STEP_SYS/2) axi_clk = ~axi_clk;
    endtask

    task clk_gen_dev();
        s_axis_aclk = 0;
        forever #(STEP_DEV/2) s_axis_aclk = ~s_axis_aclk;
    endtask

    task rst_gen();
        axi_aresetn = 0;
        s_axis_aresetn = 0;
        s_axis_i_tdata = 0;
        s_axis_q_tdata = 0;

        din_on = 0;
        din_fin = 0;
        resync = 0;

        #(STEP_SYS*10);
        axi_aresetn = 1;
        s_axis_aresetn = 1;
    endtask
    
    task file_open();
        fd_din_i = $fopen("./data_in_i.bin", "r");
        fd_din_q = $fopen("./data_in_q.bin", "r");

        fd_dout = $fopen("./data_out.bin", "w");

        if ((fd_din_q == 0) | (fd_dout == 0)) begin
            $display("File open error.");
            $finish;
        end else begin
            $display("File open.");
            write_ready = 1;
        end
    endtask
    
    task p_setting_read();
        fd_p = $fopen("./p_setting.bin", "r");
        if (fd_p == 0) begin
            $display("p_setting open error.");
            $finish;
        end else begin
            $fscanf(fd_p, "%b\n", s_axis_phase_tdata);
            $fclose(fd_p);
        end
    endtask

    task file_close();
        if (write_ready) begin
            write_ready = 0;
            $fclose(fd_dout);
        end
    endtask

    axi_transaction wr_transaction;
    axi_transaction rd_transaction;
    
    initial begin : START_system_axi_vip_0_0_MASTER
        fork
            clk_gen();
            clk_gen_dev();
            rst_gen();
            file_open();
            p_setting_read();
        join_none
        
        #(STEP_SYS*500);
    
        vip_agent = new("my VIP master", sim_full.dut.system_i.axi_vip.inst.IF);
        vip_agent.start_master();
        #(STEP_SYS*100);
        wr_transaction = vip_agent.wr_driver.create_transaction("write transaction");
        
        // PINC
        wr_transaction.set_write_cmd(4, XIL_AXI_BURST_TYPE_INCR, 0, 0, xil_axi_size_t'(xil_clog2((32)/8)));
        wr_transaction.set_data_block(pinc);
        vip_agent.wr_driver.send(wr_transaction);

        #(STEP_SYS*10);
        // POFF
        wr_transaction.set_write_cmd(8, XIL_AXI_BURST_TYPE_INCR, 0, 0, xil_axi_size_t'(xil_clog2((32)/8)));
        wr_transaction.set_data_block(poff);
        vip_agent.wr_driver.send(wr_transaction);
        #(STEP_SYS*10);

        // Channel
        for(int i = 0; i < 4; i++) begin
            wr_transaction.set_write_cmd(0, XIL_AXI_BURST_TYPE_INCR, 0, 0, xil_axi_size_t'(xil_clog2((32)/8)));
            wr_transaction.set_data_block(i);
            vip_agent.wr_driver.send(wr_transaction);
        end

        #(STEP_SYS*50);

        wr_transaction.set_write_cmd(12, XIL_AXI_BURST_TYPE_INCR, 0, 0, xil_axi_size_t'(xil_clog2((32)/8)));
        wr_transaction.set_data_block(DS_RATE);
        vip_agent.wr_driver.send(wr_transaction);


        #(STEP_SYS*50);
        wr_transaction.set_write_cmd(16, XIL_AXI_BURST_TYPE_INCR, 0, 0, xil_axi_size_t'(xil_clog2((32)/8)));
        wr_transaction.set_data_block(1);
        vip_agent.wr_driver.send(wr_transaction);
        @(posedge s_axis_aclk);
        //resync <= 1;
        @(posedge s_axis_aclk);
        resync <= 0;
        repeat(10)@(posedge s_axis_aclk);
        din_on <= 1;

        wait(finish);

        repeat(1000)@(posedge s_axis_aclk);

        $finish;
    end

    always @(posedge s_axis_aclk) begin
        if (m_axis_ddc_tvalid && din_on && write_ready) begin
            if (~finish) begin
                $fdisplay(fd_dout, "%b", data_out);
                if (counter == (4*SIM_LENGTH/DS_RATE - 1)) begin
                    finish <= 1;
                    $fclose(fd_dout);
                end else begin
                    counter <= counter + 1;
                end
            end
        end
    end

    always @(posedge s_axis_aclk) begin
        if (din_on & ~din_fin) begin
            $fscanf(fd_din_i, "%b\n", s_axis_i_tdata);
            $fscanf(fd_din_q, "%b\n", s_axis_q_tdata);
            if($feof(fd_din_q) != 0) begin
                $display("DIN fin");
                $fclose(fd_din_i);
                $fclose(fd_din_q);
                din_fin <= 1'b1;
            end
        end
    end

endmodule
