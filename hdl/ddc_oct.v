`timescale 1 ns / 1 ps

module ddc_oct(
    input wire         s_axis_aclk,

    // ADC I, 8 lanes x (12 + 4(pad)) bits
    input wire [127:0] s_axis_i_tdata,
    output wire        s_axis_i_tready,
    input wire         s_axis_i_tvalid,

    // ADC Q, 8 lanes x (12 + 4(pad)) bits
    input wire [127:0] s_axis_q_tdata,
    output wire        s_axis_q_tready,
    input wire         s_axis_q_tvalid,

    // phase input, [63:32] poff, [31:0] pinc
    input wire [63:0]  s_axis_phase_tdata,
    input wire         s_axis_phase_tvalid,
    input wire         resync,

    // DAC I, 8 lanes x (14 + 2(pad)) bits
    output wire [127:0] m_axis_ddsi_tdata,
    output wire         m_axis_ddsi_tvalid,
    input  wire         m_axis_ddsi_tready,

    // DAC Q, 8 lanes x (14 + 2(pad)) bits
    output wire [127:0] m_axis_ddsq_tdata,
    output wire         m_axis_ddsq_tvalid,
    input  wire         m_axis_ddsq_tready,

    // Oct DDC output [61:32] Q, [29:0] I
    output wire [63:0] m_axis_ddc_tdata,
    output wire        m_axis_ddc_tvalid,
    input wire         m_axis_ddc_tready
);

    localparam LATENCY_P = 4;
    localparam LATENCY_SUM = 9;
    localparam DDC_RES = 30;
    localparam DDC_PAD = 32 - DDC_RES;

    wire valid_in_dds;  // Buffered valid signal
    wire resync_dds;    // Buffered resync signal
    wire valid_out_ddc; // Buffered valid signal

    wire valid_out_dds;
    assign m_axis_ddsi_tvalid = valid_out_dds; 
    assign m_axis_ddsq_tvalid = valid_out_dds;

    wire s_axis_tvalid = s_axis_i_tvalid & s_axis_q_tvalid;

    // always ready
    assign s_axis_i_tready = 1'b1;
    assign s_axis_q_tready = 1'b1;

    // PINC/POFF preparation
    reg [31:0] pinc_buf;
    reg [31:0] poff_buf;

    wire [31:0] poff_0;
    wire [31:0] poff_1;
    wire [31:0] poff_2;
    wire [31:0] poff_3;
    wire [31:0] poff_4;
    wire [31:0] poff_5;
    wire [31:0] poff_6;
    wire [31:0] poff_7;

    wire [31:0] pinc_x2;
    wire [31:0] pinc_x3;
    wire [31:0] pinc_x4;
    wire [31:0] pinc_x5;
    wire [31:0] pinc_x6;
    wire [31:0] pinc_x7;
    wire [31:0] pinc_x8;

    wire [63:0] ddc_out_0;
    wire [63:0] ddc_out_1;
    wire [63:0] ddc_out_2;
    wire [63:0] ddc_out_3;
    wire [63:0] ddc_out_4;
    wire [63:0] ddc_out_5;
    wire [63:0] ddc_out_6;
    wire [63:0] ddc_out_7;

    // Valid signal management
    reg [LATENCY_P-1:0] p_valid_buf;
    reg [LATENCY_P-1:0] resync_buf;
    reg [LATENCY_SUM-1:0] valid_out_buf;
    reg configured = 0;

    // Sum
    wire [27:0] i_01;
    wire [27:0] i_23;
    wire [27:0] i_45;
    wire [27:0] i_67;
    wire [28:0] i_0123;
    wire [28:0] i_4567;
    wire [29:0] i_tot;

    wire [27:0] q_01;
    wire [27:0] q_23;
    wire [27:0] q_45;
    wire [27:0] q_67;
    wire [28:0] q_0123;
    wire [28:0] q_4567;
    wire [29:0] q_tot;


    /////////////////////////////////////////////////////////// Phase configuration
    always @(posedge s_axis_aclk) begin
        if (s_axis_phase_tvalid) begin
            pinc_buf <= s_axis_phase_tdata[31:0];
            poff_buf <= s_axis_phase_tdata[63:0];
        end
    end

    // Buffering
    // This buffer accounts for the latency in 'c_add' to yield phases for DDSes.
    always @(posedge s_axis_aclk) begin
        p_valid_buf = {p_valid_buf[LATENCY_P-2:0], s_axis_phase_tvalid};
        resync_buf = {resync_buf[LATENCY_P-2:0], resync};
    end

    assign valid_in_dds = p_valid_buf[LATENCY_P-1];
    assign resync_dds = resync_buf[LATENCY_P-1];

    // Phase increment and offset calculation for oct-mode operation
    assign pinc_x2 = {pinc_buf[30:0], 1'b0};
    assign pinc_x3 = pinc_buf + pinc_x2;
    assign pinc_x4 = {pinc_buf[29:0], 2'b0};
    assign pinc_x5 = pinc_buf + pinc_x4;
    assign pinc_x6 = pinc_x2 + pinc_x4;
    assign pinc_x7 = pinc_x3 + pinc_x4;
    assign pinc_x8 = {pinc_buf[28:0], 3'b0};

    // phase adder
    adder_phase_oct add_p_0(
        .clk(s_axis_aclk),
        .a(poff_buf),
        .b(32'b0),
        .s(poff_0)
    );

    adder_phase_oct add_p_1(
        .clk(s_axis_aclk),
        .a(poff_buf),
        .b(pinc_buf),
        .s(poff_1)
    );

    adder_phase_oct add_p_2(
        .clk(s_axis_aclk),
        .a(poff_buf),
        .b(pinc_x2),
        .s(poff_2)
    );

    adder_phase_oct add_p_3(
        .clk(s_axis_aclk),
        .a(poff_buf),
        .b(pinc_x3),
        .s(poff_3)
    );

    adder_phase_oct add_p_4(
        .clk(s_axis_aclk),
        .a(poff_buf),
        .b(pinc_x4),
        .s(poff_4)
    );

    adder_phase_oct add_p_5(
        .clk(s_axis_aclk),
        .a(poff_buf),
        .b(pinc_x5),
        .s(poff_5)
    );

    adder_phase_oct add_p_6(
        .clk(s_axis_aclk),
        .a(poff_buf),
        .b(pinc_x6),
        .s(poff_6)
    );

    adder_phase_oct add_p_7(
        .clk(s_axis_aclk),
        .a(poff_buf),
        .b(pinc_x7),
        .s(poff_7)
    );

    // DDC instantiation
    ddc_core ddc_0(
        .s_axis_aclk(s_axis_aclk),
        .s_axis_tdata({s_axis_q_tdata[15:0], s_axis_i_tdata[15:0]}), // [26:16] Q, [11:0] I
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_phase_tdata({poff_0, pinc_x8}),
        .s_axis_phase_tvalid(valid_in_dds),
        .resync(resync_dds),
        .m_axis_dds_tdata({m_axis_ddsq_tdata[15:0], m_axis_ddsi_tdata[15:0]}),
        .m_axis_dds_tvalid(valid_out_dds),
        .m_axis_ddc_tdata(ddc_out_0),
        .m_axis_ddc_tvalid(valid_out_ddc)
    );

    ddc_core ddc_1(
        .s_axis_aclk(s_axis_aclk),
        .s_axis_tdata({s_axis_q_tdata[31:16], s_axis_i_tdata[31:16]}),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_phase_tdata({poff_1, pinc_x8}),
        .s_axis_phase_tvalid(valid_in_dds),
        .resync(resync_dds),
        .m_axis_dds_tdata({m_axis_ddsq_tdata[31:16], m_axis_ddsi_tdata[31:16]}),
        .m_axis_ddc_tdata(ddc_out_1)
    );

    ddc_core ddc_2(
        .s_axis_aclk(s_axis_aclk),
        .s_axis_tdata({s_axis_q_tdata[47:32], s_axis_i_tdata[47:32]}),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_phase_tdata({poff_2, pinc_x8}),
        .s_axis_phase_tvalid(valid_in_dds),
        .resync(resync_dds),
        .m_axis_dds_tdata({m_axis_ddsq_tdata[47:32], m_axis_ddsi_tdata[47:32]}),
        .m_axis_ddc_tdata(ddc_out_2)
    );

    ddc_core ddc_3(
        .s_axis_aclk(s_axis_aclk),
        .s_axis_tdata({s_axis_q_tdata[63:48], s_axis_i_tdata[63:48]}), // [26:16] Q, [11:0] I
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_phase_tdata({poff_3, pinc_x8}),
        .s_axis_phase_tvalid(valid_in_dds),
        .resync(resync_dds),
        .m_axis_dds_tdata({m_axis_ddsq_tdata[63:48], m_axis_ddsi_tdata[63:48]}),
        .m_axis_ddc_tdata(ddc_out_3)
    );

    ddc_core ddc_4(
        .s_axis_aclk(s_axis_aclk),
        .s_axis_tdata({s_axis_q_tdata[79:64], s_axis_i_tdata[79:64]}), // [26:16] Q, [11:0] I
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_phase_tdata({poff_4, pinc_x8}),
        .s_axis_phase_tvalid(valid_in_dds),
        .resync(resync_dds),
        .m_axis_dds_tdata({m_axis_ddsq_tdata[79:64], m_axis_ddsi_tdata[79:64]}),
        .m_axis_ddc_tdata(ddc_out_4)
    );

    ddc_core ddc_5(
        .s_axis_aclk(s_axis_aclk),
        .s_axis_tdata({s_axis_q_tdata[95:80], s_axis_i_tdata[95:80]}), // [26:16] Q, [11:0] I
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_phase_tdata({poff_5, pinc_x8}),
        .s_axis_phase_tvalid(valid_in_dds),
        .resync(resync_dds),
        .m_axis_dds_tdata({m_axis_ddsq_tdata[95:80], m_axis_ddsi_tdata[95:80]}),
        .m_axis_ddc_tdata(ddc_out_5)
    );

    ddc_core ddc_6(
        .s_axis_aclk(s_axis_aclk),
        .s_axis_tdata({s_axis_q_tdata[111:96], s_axis_i_tdata[111:96]}), // [26:16] Q, [11:0] I
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_phase_tdata({poff_6, pinc_x8}),
        .s_axis_phase_tvalid(valid_in_dds),
        .resync(resync_dds),
        .m_axis_dds_tdata({m_axis_ddsq_tdata[111:96], m_axis_ddsi_tdata[111:96]}),
        .m_axis_ddc_tdata(ddc_out_6)
    );

    ddc_core ddc_7(
        .s_axis_aclk(s_axis_aclk),
        .s_axis_tdata({s_axis_q_tdata[127:112], s_axis_i_tdata[127:112]}), // [26:16] Q, [11:0] I
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_phase_tdata({poff_7, pinc_x8}),
        .s_axis_phase_tvalid(valid_in_dds),
        .resync(resync_dds),
        .m_axis_dds_tdata({m_axis_ddsq_tdata[127:112], m_axis_ddsi_tdata[127:112]}),
        .m_axis_ddc_tdata(ddc_out_7)
    );

    ///////////////////////////////////////////////////////// Output adder
    // 1st stage
    adder_1st_oct add_i_01(
        .clk(s_axis_aclk),
        .a(ddc_out_0[26:0]),
        .b(ddc_out_1[26:0]),
        .s(i_01)
    );

    adder_1st_oct add_i_23(
        .clk(s_axis_aclk),
        .a(ddc_out_2[26:0]),
        .b(ddc_out_3[26:0]),
        .s(i_23)
    );

    adder_1st_oct add_i_45(
        .clk(s_axis_aclk),
        .a(ddc_out_4[26:0]),
        .b(ddc_out_5[26:0]),
        .s(i_45)
    );

    adder_1st_oct add_i_67(
        .clk(s_axis_aclk),
        .a(ddc_out_6[26:0]),
        .b(ddc_out_7[26:0]),
        .s(i_67)
    );
    adder_1st_oct add_q_01(
        .clk(s_axis_aclk),
        .a(ddc_out_0[58:32]),
        .b(ddc_out_1[58:32]),
        .s(q_01)
    );

    adder_1st_oct add_q_23(
        .clk(s_axis_aclk),
        .a(ddc_out_2[58:32]),
        .b(ddc_out_3[58:32]),
        .s(q_23)
    );

    adder_1st_oct add_q_45(
        .clk(s_axis_aclk),
        .a(ddc_out_4[58:32]),
        .b(ddc_out_5[58:32]),
        .s(q_45)
    );

    adder_1st_oct add_q_67(
        .clk(s_axis_aclk),
        .a(ddc_out_6[58:32]),
        .b(ddc_out_7[58:32]),
        .s(q_67)
    );

    // 2nd stage
    adder_2nd_oct add_i_0123(
        .clk(s_axis_aclk),
        .a(i_01),
        .b(i_23),
        .s(i_0123)
    );

    adder_2nd_oct add_i_4567(
        .clk(s_axis_aclk),
        .a(i_45),
        .b(i_67),
        .s(i_4567)
    );

    adder_2nd_oct add_q_0123(
        .clk(s_axis_aclk),
        .a(q_01),
        .b(q_23),
        .s(q_0123)
    );

    adder_2nd_oct add_q_4567(
        .clk(s_axis_aclk),
        .a(q_45),
        .b(q_67),
        .s(q_4567)
    );

    // 3rd stage
    adder_3rd_oct add_i_tot(
        .clk(s_axis_aclk),
        .a(i_0123),
        .b(i_4567),
        .s(i_tot)
    );

    adder_3rd_oct add_q_tot(
        .clk(s_axis_aclk),
        .a(q_0123),
        .b(q_4567),
        .s(q_tot)
    );

    /////////////////////////////////////////////////////////////////// M_AXIS interface for oct DDC output
    assign m_axis_ddc_tdata = {{(DDC_PAD){q_tot[DDC_RES-1]}}, q_tot, {(DDC_PAD){i_tot[DDC_RES-1]}}, i_tot};

    // Buffer to account for the latencies in c_add cores.
    always @(posedge s_axis_aclk) begin
        valid_out_buf <= {valid_out_buf[LATENCY_SUM-2:0], valid_out_ddc};
    end
    assign m_axis_ddc_tvalid = valid_out_buf[LATENCY_SUM-1];

endmodule
