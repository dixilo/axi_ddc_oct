`timescale 1ns / 1ps

module sim_ddc_oct(
    );
    
    parameter STEP_SYS = 40;
    parameter SIM_LENGTH = 65536;

    // input
    logic         s_axis_aclk;

    logic [127:0] s_axis_i_tdata;
    logic         s_axis_i_tready;
    logic         s_axis_i_tvalid;
    logic [127:0] s_axis_q_tdata;
    logic         s_axis_q_tready;
    logic         s_axis_q_tvalid;

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

    wire [15:0] ddsi_0 = m_axis_ddsi_tdata[15:0];
    wire [15:0] ddsi_1 = m_axis_ddsi_tdata[31:16];
    wire [15:0] ddsi_2 = m_axis_ddsi_tdata[47:32];
    wire [15:0] ddsi_3 = m_axis_ddsi_tdata[63:48];
    wire [15:0] ddsi_4 = m_axis_ddsi_tdata[79:64];
    wire [15:0] ddsi_5 = m_axis_ddsi_tdata[95:80];
    wire [15:0] ddsi_6 = m_axis_ddsi_tdata[111:96];
    wire [15:0] ddsi_7 = m_axis_ddsi_tdata[127:112];
    
    wire [15:0] ddsq_0 = m_axis_ddsq_tdata[15:0];
    wire [15:0] ddsq_1 = m_axis_ddsq_tdata[31:16];
    wire [15:0] ddsq_2 = m_axis_ddsq_tdata[47:32];
    wire [15:0] ddsq_3 = m_axis_ddsq_tdata[63:48];
    wire [15:0] ddsq_4 = m_axis_ddsq_tdata[79:64];
    wire [15:0] ddsq_5 = m_axis_ddsq_tdata[95:80];
    wire [15:0] ddsq_6 = m_axis_ddsq_tdata[111:96];
    wire [15:0] ddsq_7 = m_axis_ddsq_tdata[127:112];
    

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

    ddc_oct dut(.*);

    task clk_gen();
        s_axis_aclk = 0;
        forever #(STEP_SYS/2) s_axis_aclk = ~s_axis_aclk;
    endtask
    
    task rst_gen();
        s_axis_phase_tdata = 0;
        s_axis_phase_tvalid = 0;
        
        resync = 0;
        
        s_axis_i_tvalid = 0;
        s_axis_q_tvalid = 0;

        m_axis_ddsi_tready = 1;
        m_axis_ddsq_tready = 1;
        m_axis_ddc_tready = 1;

        din_on = 0;
        din_fin = 0;
        
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
        @(posedge s_axis_aclk);
        s_axis_phase_tvalid <= 1;        
        @(posedge s_axis_aclk);
        repeat(20) @(posedge s_axis_aclk);
        din_on <= 1;
        @(posedge s_axis_aclk);
        wait(finish);

        s_axis_phase_tvalid <= 0;

        #(STEP_SYS*30);
        file_close();
        #(STEP_SYS*30);
        $finish;
    end
        
    always @(posedge s_axis_aclk) begin
        if (m_axis_ddc_tvalid && write_ready) begin
            if (~finish) begin
                $fdisplay(fd_dout, "%b", m_axis_ddc_tdata);
                if (counter == (SIM_LENGTH - 1)) begin
                    finish <= 1;
                end else begin
                    counter <= counter + 1;
                end
            end
        end
    end

    always @(posedge s_axis_aclk) begin
        if (din_on & ~din_fin) begin
            if($feof(fd_din_q) != 0) begin
                $display("DIN fin");
                $fclose(fd_din_i);
                $fclose(fd_din_q);
                din_fin <= 1'b1;
                s_axis_i_tvalid <= 1'b0;
                s_axis_q_tvalid <= 1'b0;
            end

            $fscanf(fd_din_i, "%b\n", s_axis_i_tdata);
            $fscanf(fd_din_q, "%b\n", s_axis_q_tdata);
            s_axis_i_tvalid <= 1'b1;
            s_axis_q_tvalid <= 1'b1;
        end
    end

endmodule
