`timescale 1ns / 1ps

module sim_ddc_quad(
    );
    
    parameter STEP_SYS = 40;
    parameter SIM_LENGTH = 65536;

    // input
    logic valid_in;
    logic clk;
    logic [31:0] data_in_0;
    logic [31:0] data_in_1;
    logic [31:0] data_in_2;
    logic [31:0] data_in_3;
    logic p_valid;
    assign p_valid = valid_in;

    // Output
    logic valid_out;
    logic [63:0] data_out;

    // Feed to DDS compiler
    logic [19:0] pinc;
    logic [19:0] poff;

    // Control data
    logic din_on;
    logic din_fin;
    logic write_on;

    // write output
    integer fd_din_0;
    integer fd_din_1;
    integer fd_din_2;
    integer fd_din_3;

    integer fd_dout;
    logic write_ready = 0;
    logic [$clog2(SIM_LENGTH)-1:0] counter = 0;
    logic finish = 0;
    logic resync = 0;

    // read setting
    integer fd_p;

    ddc_quad dut(.*);

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
        repeat(10) @(posedge clk);
        din_on <= 1;
        @(posedge clk);
        wait(finish);

        valid_in <= 0;

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
