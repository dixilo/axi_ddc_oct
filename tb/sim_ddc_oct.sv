`timescale 1ns / 1ps

module sim_ddc_oct(
    );
    
    parameter STEP_SYS = 40;
    parameter SIM_LENGTH = 65536;

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

    // Control data
    logic din_on;
    logic din_fin;
    logic write_on;

    // File descriptors
    integer fd_din_i;
    integer fd_din_q;
    integer fd_dout;

    logic write_ready = 0;
    logic [$clog2(SIM_LENGTH)-1:0] counter = 0;
    logic finish = 0;

    // read setting
    integer fd_p;

    ddc_quad dut(.*);

    task clk_gen();
        s_axis_aclk = 0;
        forever #(STEP_SYS/2) clk = ~clk;
    endtask
    
    task rst_gen();
        s_axis_phase_tdata = 0;
        din_on = 0;
        din_fin = 0;
        valid_in = 0;
        write_on = 0;
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
        
    initial begin
        fork
            clk_gen();
            rst_gen();
        join_none
        #(STEP_SYS*10);
        file_open();
        p_setting_read();

        #(STEP_SYS*10);
        @(posedge clk);
        s_axis_phase_tvalid <= 1;        
        @(posedge clk);
        repeat(10) @(posedge clk);
        din_on <= 1;
        @(posedge clk);
        wait(finish);

        s_axis_phase_tvalid <= 0;

        #(STEP_SYS*30);
        file_close();
        #(STEP_SYS*30);
        $finish;
    end
        
    always @(posedge clk) begin
        if (valid_out && write_ready) begin
            if (~finish) begin
                $fdisplay(fd_dout, "%b", data_out);
                if (counter == (SIM_LENGTH - 1)) begin
                    finish <= 1;
                end else begin
                    counter <= counter + 1;
                end
            end
        end
    end

    always @(posedge clk) begin
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
