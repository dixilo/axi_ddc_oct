`timescale 1ns / 1ps

module sim_accum();
    
    localparam STEP_SYS = 40;
    localparam SIM_LENGTH = 128;

    // input
    logic clk;
    logic rst;
    logic valid_in;
    logic valid_out;
    logic [17:0] length;
    logic [30:0] data_in;
    logic [47:0] data_out;

    accumulator accum_inst (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .length(length),
        .data_in(data_in),
        .valid_out(valid_out),
        .data_out(data_out)
    );

    task clk_gen();
        clk = 0;
        forever #(STEP_SYS/2) clk = ~clk;
    endtask
    
    task rst_gen();
        length = 0;
        rst = 0;
        data_in = 0;
        @(posedge clk);
        rst = 1;
        repeat(10) @(posedge clk);
        rst = 0;
    endtask
    
        
    initial begin
        fork
            clk_gen();
            rst_gen();
        join_none
        repeat(20) @(posedge clk)
        @(posedge clk);
        length = 16;
        @(posedge clk);
        data_in <= 1;
        repeat(20) @(posedge clk);
        for (int i = 0; i < SIM_LENGTH; i++) begin
            valid_in <= 1;
            @(posedge clk);
        end
        length <= 4;
        for (int i = 0; i < SIM_LENGTH; i++) begin
            valid_in <= 1;
            @(posedge clk);
        end
        valid_in <= 0;
        repeat(100) @(posedge clk);
        $finish;
    end
        
endmodule
