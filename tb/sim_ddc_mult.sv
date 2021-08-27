`timescale 1ns / 1ps

module sim_ddc_mult(
    );
    
    parameter STEP_SYS = 40;
    parameter SIM_LENGTH = 65536;

    // input
    logic [47:0] phase_in_0;
    logic [47:0] phase_in_1;
    logic [47:0] phase_in_2;
    logic [47:0] phase_in_3;
    logic valid_in;
    logic clk;
    logic [31:0] data_in_0;
    logic [31:0] data_in_1;
    logic [31:0] data_in_2;
    logic [31:0] data_in_3;

    // Output
    logic valid_out;
    logic [63:0] ddc_out_0;
    logic [63:0] ddc_out_1;
    logic [63:0] ddc_out_2;
    logic [63:0] ddc_out_3;

    // Feed to DDS compiler
    logic [19:0] pinc;
    logic [19:0] poff;
    logic [19:0] pinc_x4;
    logic [19:0] pinc_x2;
    logic [19:0] pinc_x3;
    assign pinc_x4 = {pinc[17:0], 2'b0};
    assign pinc_x2 = {pinc[18:0], 1'b0};
    assign pinc_x3 = pinc + pinc_x2;
    assign phase_in_0 = {4'b0, poff          , 4'b0, pinc_x4};
    assign phase_in_1 = {4'b0, poff +    pinc, 4'b0, pinc_x4};
    assign phase_in_2 = {4'b0, poff + pinc_x2, 4'b0, pinc_x4};
    assign phase_in_3 = {4'b0, poff + pinc_x3, 4'b0, pinc_x4};

    // Control data
    logic din_on;
    logic din_fin;
    logic write_on;

    // write output
    integer fd_din_0;
    integer fd_din_1;
    integer fd_din_2;
    integer fd_din_3;

    integer fd_dout_0;
    integer fd_dout_1;
    integer fd_dout_2;
    integer fd_dout_3;
    logic write_ready = 0;
    logic [$clog2(SIM_LENGTH)-1:0] counter = 0;
    logic finish = 0;

    // read setting
    integer fd_p;

    ddc_core dc_0(
        .clk(clk),
        .data_in(data_in_0),
        .valid_in(valid_in),
        .phase_in(phase_in_0),
        .valid_out(valid_out),
        .ddc_out(ddc_out_0)
    );

    ddc_core dc_1(
        .clk(clk),
        .data_in(data_in_1),
        .valid_in(valid_in),
        .phase_in(phase_in_1),
        .valid_out(),
        .ddc_out(ddc_out_1)
    );

    ddc_core dc_2(
        .clk(clk),
        .data_in(data_in_2),
        .valid_in(valid_in),
        .phase_in(phase_in_2),
        .valid_out(),
        .ddc_out(ddc_out_2)
    );

    ddc_core dc_3(
        .clk(clk),
        .data_in(data_in_3),
        .valid_in(valid_in),
        .phase_in(phase_in_3),
        .valid_out(),
        .ddc_out(ddc_out_3)
    );

    task clk_gen();
        clk = 0;
        forever #(STEP_SYS/2) clk = ~clk;
    endtask
    
    task rst_gen();
        pinc = 0;
        poff = 0;
        din_on = 0;
        din_fin = 0;
        valid_in = 0;
        write_on = 0;
    endtask
    
    task file_open();
        fd_din_0 = $fopen("./data_in_0.bin", "r");
        fd_din_1 = $fopen("./data_in_1.bin", "r");
        fd_din_2 = $fopen("./data_in_2.bin", "r");
        fd_din_3 = $fopen("./data_in_3.bin", "r");

        fd_dout_0 = $fopen("./data_out_0.bin", "w");
        fd_dout_1 = $fopen("./data_out_1.bin", "w");
        fd_dout_2 = $fopen("./data_out_2.bin", "w");
        fd_dout_3 = $fopen("./data_out_3.bin", "w");

        if ((fd_din_3 == 0) | (fd_dout_3 == 0)) begin
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
            $fclose(fd_dout_0);
            $fclose(fd_dout_1);
            $fclose(fd_dout_2);
            $fclose(fd_dout_3);
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
        valid_in <= 1;
        @(posedge clk);
        valid_in <= 0;
        repeat(7) @(posedge clk);
        din_on <= 1;
        repeat(7) @(posedge clk);
        write_on <= 1;
        @(posedge clk);
        wait(finish);

        valid_in <= 0;

        #(STEP_SYS*30);
        file_close();
        #(STEP_SYS*30);
        $finish;
    end
        
    always @(posedge clk) begin
        if (write_on && write_ready) begin
            if (~finish) begin
                $fdisplay(fd_dout_0, "%b", ddc_out_0);
                $fdisplay(fd_dout_1, "%b", ddc_out_1);
                $fdisplay(fd_dout_2, "%b", ddc_out_2);
                $fdisplay(fd_dout_3, "%b", ddc_out_3);
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
