`timescale 1 ns / 1 ps

module ddc_oct(
    input wire s_axis_aclk,

    // ADC I, 8 lanes x (12 + 4(pad)) bits
    input wire [127:0] s_axis_i_tdata,
    output wire        s_axis_i_tready,
    input wire         s_axis_i_tvalid,

    // ADC Q, 8 lanes x (12 + 4(pad)) bits
    input wire [127:0] s_axis_q_tdata,
    output wire        s_axis_q_tready,
    input wire         s_axis_q_tvalid,

    input wire [63:0]  s_axis_phase_tdata,
    input wire         s_axis_phase_tvalid,
    input wire         resync,

    output valid_out,
    output [63:0] data_out
);

    localparam LATENCY_P = 4;
    localparam LATENCY_SUM = 6;

    wire valid_in_dds;
    wire resync_dds;
    wire valid_out_ddc;

    reg [19:0] pinc_buf;
    reg [19:0] poff_buf;

    wire [19:0] poff_0;
    wire [19:0] poff_1;
    wire [19:0] poff_2;
    wire [19:0] poff_3;

    wire [63:0] ddc_out_0;
    wire [63:0] ddc_out_1;
    wire [63:0] ddc_out_2;
    wire [63:0] ddc_out_3;

    wire [19:0] pinc_x2;
    wire [19:0] pinc_x3;
    wire [19:0] pinc_x4;

    // Valid signal management
    reg [LATENCY_P-1:0] p_valid_buf;
    reg [LATENCY_P-1:0] resync_buf;
    reg [LATENCY_SUM-1:0] valid_out_buf;
    reg configured = 0;

    // Sum
    wire [29:0] i_03;
    wire [29:0] q_03;
    wire [29:0] i_12;
    wire [29:0] q_12;
    wire [30:0] i_tot;
    wire [30:0] q_tot;

    assign data_out = {q_tot[30], q_tot, i_tot[30], i_tot};

    always @(posedge clk) begin
        if (p_valid) begin
            pinc_buf <= pinc;
            poff_buf <= poff;
        end
    end

    always @(posedge clk) begin
        p_valid_buf = {p_valid_buf[LATENCY_P-2:0], p_valid};
        resync_buf = {resync_buf[LATENCY_P-2:0], resync};
    end
    assign valid_in_dds = p_valid_buf[LATENCY_P-1];
    assign resync_dds = resync_buf[LATENCY_P-1];

    always @(posedge clk) begin
        if (valid_in_dds) begin
            configured <= 1;
        end
    end

    always @(posedge clk) begin
        valid_out_buf = {valid_out_buf[LATENCY_SUM-2:0], valid_out_ddc};
    end
    assign valid_out = valid_out_buf[LATENCY_SUM-1];

    // Phase increment and offset calculation for quad-mode operation
    assign pinc_x4 = {pinc_buf[17:0], 2'b0};
    assign pinc_x2 = {pinc_buf[18:0], 1'b0};
    assign pinc_x3 = pinc_buf + pinc_x2;

    // phase adder
    adder_phase_dd2 add_0(
        .clk(clk),
        .a(poff_buf),
        .b(20'b0),
        .s(poff_0)
    );

    adder_phase_dd2 add_1(
        .clk(clk),
        .a(poff_buf),
        .b(pinc_buf),
        .s(poff_1)
    );

    adder_phase_dd2 add_2(
        .clk(clk),
        .a(poff_buf),
        .b(pinc_x2),
        .s(poff_2)
    );

    adder_phase_dd2 add_3(
        .clk(clk),
        .a(poff_buf),
        .b(pinc_x3),
        .s(poff_3)
    );

    // DDC instantiation
    ddc_core ddc_0(
        .clk(clk),
        .data_in(data_in_0),
        .valid_in(valid_in_dds | configured),
        .resync(resync_dds),
        .phase_in({4'b0, poff_0, 4'b0, pinc_x4}),
        .valid_out(valid_out_ddc),
        .ddc_out(ddc_out_0)
    );

    ddc_core ddc_1(
        .clk(clk),
        .data_in(data_in_1),
        .resync(resync_dds),
        .valid_in(valid_in_dds | configured),
        .phase_in({4'b0, poff_1, 4'b0, pinc_x4}),
        .ddc_out(ddc_out_1)
    );

    ddc_core ddc_2(
        .clk(clk),
        .data_in(data_in_2),
        .resync(resync_dds),
        .valid_in(valid_in_dds | configured),
        .phase_in({4'b0, poff_2, 4'b0, pinc_x4}),
        .ddc_out(ddc_out_2)
    );

    ddc_core ddc_3(
        .clk(clk),
        .data_in(data_in_3),
        .resync(resync_dds),
        .valid_in(valid_in_dds | configured),
        .phase_in({4'b0, poff_3, 4'b0, pinc_x4}),
        .ddc_out(ddc_out_3)
    );


    // Output adder
    adder_1st_dd2 add_i_03(
        .clk(clk),
        .a(ddc_out_0[28:0]),
        .b(ddc_out_3[28:0]),
        .s(i_03)
    );

    adder_1st_dd2 add_q_03(
        .clk(clk),
        .a(ddc_out_0[60:32]),
        .b(ddc_out_3[60:32]),
        .s(q_03)
    );

    adder_1st_dd2 add_i_12(
        .clk(clk),
        .a(ddc_out_1[28:0]),
        .b(ddc_out_2[28:0]),
        .s(i_12)
    );

    adder_1st_dd2 add_q_12(
        .clk(clk),
        .a(ddc_out_1[60:32]),
        .b(ddc_out_2[60:32]),
        .s(q_12)
    );

    adder_2nd_dd2 add_i_tot(
        .clk(clk),
        .a(i_03),
        .b(i_12),
        .s(i_tot)
    );

    adder_2nd_dd2 add_q_tot(
        .clk(clk),
        .a(q_03),
        .b(q_12),
        .s(q_tot)
    );

    wire [7:0] s_axis_config_tdata = 8'b0;
    wire s_axis_config_tvalid = 1'b0;
    wire s_axis_config_tready;
    wire [31:0] s_axis_data_tdata = data_in_0;
    wire s_axis_data_tvalid = 1'b1;
    wire s_axis_data_tready;
    wire s_axis_data_tlast = 1'b0;
    wire [63:0] m_axis_data_tdata;
    wire [15:0] m_axis_data_tuser;
    wire m_axis_data_tvalid;
    wire m_axis_data_tready = 1'b1;
    wire m_axis_data_tlast;

endmodule
