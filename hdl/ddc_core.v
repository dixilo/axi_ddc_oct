`timescale 1 ns / 1 ps

module ddc_core(
    // ADC input
    input wire        s_axis_aclk,
    input wire [31:0] s_axis_tdata, // [26:16] Q, [11:0] I
    input wire        s_axis_tvalid,
    output wire       s_axis_tready,

    // Phase input
    input wire [63:0] s_axis_phase_tdata,
    input wire        s_axis_phase_tvalid,

    // DDS output
    output wire [31:0] m_axis_dds_tdata, // [29:16] Q, [13:0] I
    output wire        m_axis_dds_tvalid,

    // DDC output
    output wire [63:0] m_axis_ddc_tdata, // [58:32] Q, [26:0] I
    output wire        m_axis_ddc_tvalid,

    input wire resync
);

    localparam DDS_RES = 14;
    localparam ADC_RES = 12;
    localparam MUL_RES = 26;
    localparam DDC_PAD = 32 - MUL_RES;
    localparam DDS_PAD = 16 - DDS_RES;

    localparam DDC_LATENCY = 6;
    localparam DDS_LATENCY = 8;

    wire dds_valid;
    wire [31:0] dds_out;

    // Convention
    wire [DDS_RES-1:0] cos_dds;
    wire [DDS_RES-1:0] sin_dds;
    wire [ADC_RES-1:0] cos_data;
    wire [ADC_RES-1:0] sin_data;

    // Result of multiplication
    wire [MUL_RES-1:0] coscos;
    wire [MUL_RES-1:0] cossin;
    wire [MUL_RES-1:0] sincos;
    wire [MUL_RES-1:0] sinsin;

    // Result of sum
    wire [MUL_RES:0] out_i;
    wire [MUL_RES:0] out_q;
    
    // Valid buffering
    reg [DDS_LATENCY-1:0] dds_valid_buf = 0;
    reg [DDC_LATENCY-1:0] ddc_valid_buf = 0;
    reg p_conf = 0;

    assign cos_dds = dds_out[DDS_RES-1:0];
    assign sin_dds = dds_out[DDS_RES+15:16];
    assign cos_data = s_axis_tdata[ADC_RES-1:0];
    assign sin_data = s_axis_tdata[ADC_RES+15:16];

    assign m_axis_ddc_tdata = {{(DDC_PAD){out_q[MUL_RES]}}, out_q, {(DDC_PAD){out_i[MUL_RES]}}, out_i};
    assign m_axis_dds_tdata = {{(DDS_PAD){sin_dds[DDS_RES-1]}}, sin_dds, {(DDS_PAD){cos_dds[DDS_RES-1]}}, cos_dds};

    dds_oct dds_inst(
        .aclk(s_axis_aclk),
        .s_axis_phase_tvalid(s_axis_phase_tvalid),
        .s_axis_phase_tdata({resync, s_axis_phase_tdata}), // resync, poff [63:32], pinc [31:0], 65 bit
        .m_axis_data_tvalid(dds_valid),
        .m_axis_data_tdata(dds_out) // cos [13:0], sin [29:16], 32 bit width
    );

    // Phase configured
    always @(posedge s_axis_aclk) begin
        if (s_axis_phase_tvalid)
            p_conf <= 1;
        else
            p_conf <= p_conf;
    end

    //// DDS valid generation
    // always @(posedge s_axis_aclk) begin
    //     dds_valid_buf <= {dds_valid_buf[DDS_LATENCY-2:0], p_conf};
    // end
    // assign m_axis_dds_tvalid = dds_valid_buf[DDS_LATENCY-1];

    assign m_axis_dds_tvalid = dds_valid;

    // DDC valid generation
    always @(posedge s_axis_aclk) begin
        ddc_valid_buf[DDC_LATENCY-1:1] <= ddc_valid_buf[DDC_LATENCY-2:0];
        ddc_valid_buf[0] <= s_axis_tvalid & m_axis_dds_tvalid;
    end
    assign m_axis_ddc_tvalid = ddc_valid_buf[DDC_LATENCY-1];

    // Multiplier 12 x 14 -> 26
    multiplier_oct coscos_mult(
        .clk(s_axis_aclk),
        .a(cos_data),
        .b(cos_dds),
        .p(coscos)
    );

    multiplier_oct cossin_mult(
        .clk(s_axis_aclk),
        .a(cos_data),
        .b(sin_dds),
        .p(cossin)
    );

    multiplier_oct sincos_mult(
        .clk(s_axis_aclk),
        .a(sin_data),
        .b(cos_dds),
        .p(sincos)
    );

    multiplier_oct sinsin_mult(
        .clk(s_axis_aclk),
        .a(sin_data),
        .b(sin_dds),
        .p(sinsin)
    );

    // Adder 26 + 26 -> 27
    adder_oct sum_i(
        .clk(s_axis_aclk),
        .a(coscos),
        .b(sinsin),
        .s(out_i)
    );

    subtractor_oct sub_q(
        .clk(s_axis_aclk),
        .a(sincos),
        .b(cossin),
        .s(out_q)
    );

    assign s_axis_tready = 1'b1;

endmodule