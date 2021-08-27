`timescale 1 ns / 1 ps

module accumulator #(
    parameter integer LEN_WIDTH = 18,
    parameter integer DATA_WIDTH = 31
)(
    input clk,
    input rst,
    input valid_in,
    input [LEN_WIDTH-1:0] length,
    input [DATA_WIDTH-1:0] data_in,

    output valid_out,
    output [47:0] data_out
);

    localparam LATENCY = 2;
    // Accumulation length
    reg [LEN_WIDTH-1:0] length_buf;
    wire length_changed;
    
    // Counter
    reg [LEN_WIDTH-1:0] counter;
    wire counter_max;

    // Soft reset
    wire srst;
    wire bypass;
    
    // Valid generation
    reg [LATENCY-1:0] valid_buf; 

    assign srst = length_changed | counter_max;

    // Length logic
    always @(posedge clk) begin
        length_buf <= length;
    end
    assign length_changed = (length != length_buf);

    // Counter logic
    always @(posedge clk) begin
        if(rst | srst) begin
            counter = 0;
        end else begin
            if (valid_in) begin
                counter <= counter + 1;
            end
        end
    end

    assign counter_max = (counter == (length - 1));

    // Accumulator
    c_accum_dd2 accum_inst(
        .clk(clk),
        .bypass(bypass),
        .b(data_in),
        .q(data_out)
    );
    
    assign bypass = (counter == 0);
    
    // Valid
    always @(posedge clk) begin
        valid_buf <= {valid_buf[LATENCY-2:0],counter_max};
    end
    assign valid_out = valid_buf[LATENCY-1];

endmodule