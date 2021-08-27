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

    logic axi_aresetn;
    logic axi_clk;
    logic [31:0]data_in_0;
    logic [31:0]data_in_1;
    logic [31:0]data_in_2;
    logic [31:0]data_in_3;
    logic [95:0]data_out;
    logic dev_clk;
    logic dev_rst;
    logic valid_out;
    logic resync;
    
    system_wrapper dut(.*);

    logic [19:0] pinc;
    logic [19:0] poff;

    // Utility
    integer fd_din_0;
    integer fd_din_1;
    integer fd_din_2;
    integer fd_din_3;

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
        dev_clk = 0;
        forever #(STEP_DEV/2) dev_clk = ~dev_clk;
    endtask
    
    task rst_gen();
        axi_aresetn = 0;
        dev_rst = 1;
        data_in_0 = 0;
        data_in_1 = 0;
        data_in_2 = 0;
        data_in_3 = 0;
        din_on = 0;
        din_fin = 0;
        resync = 0;

        #(STEP_SYS*10);
        axi_aresetn = 1;
        dev_rst = 0;
    endtask
    
    task file_open();
        fd_din_0 = $fopen("./data_in_0.bin", "r");
        fd_din_1 = $fopen("./data_in_1.bin", "r");
        fd_din_2 = $fopen("./data_in_2.bin", "r");
        fd_din_3 = $fopen("./data_in_3.bin", "r");

        fd_dout = $fopen("./data_out.bin", "w");

        if ((fd_din_3 == 0) | (fd_dout == 0)) begin
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
            $fscanf(fd_p, "%b\n", pinc);
            $fscanf(fd_p, "%b\n", poff);
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
        wr_transaction.set_data_block({12'b0, pinc});
        vip_agent.wr_driver.send(wr_transaction);

        #(STEP_SYS*10);
        // POFF
        wr_transaction.set_write_cmd(8, XIL_AXI_BURST_TYPE_INCR, 0, 0, xil_axi_size_t'(xil_clog2((32)/8)));
        wr_transaction.set_data_block({12'b0, poff});
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
        @(posedge dev_clk);
        //resync <= 1;
        @(posedge dev_clk);
        resync <= 0;
        repeat(10)@(posedge dev_clk);
        din_on <= 1;

        wait(finish);

       repeat(1000)@(posedge dev_clk);

        $finish;
    end
    
    always @(posedge dev_clk) begin
        if (valid_out && din_on && write_ready) begin
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

    always @(posedge dev_clk) begin
        if (din_on & ~din_fin) begin
            $fscanf(fd_din_0, "%b\n", data_in_0);
            $fscanf(fd_din_1, "%b\n", data_in_1);
            $fscanf(fd_din_2, "%b\n", data_in_2);
            $fscanf(fd_din_3, "%b\n", data_in_3);
            if($feof(fd_din_3) != 0) begin
                $display("DIN fin");
                $fclose(fd_din_0);
                $fclose(fd_din_1);
                $fclose(fd_din_2);
                $fclose(fd_din_3);
                din_fin <= 1'b1;
            end
        end
    end

    
endmodule
