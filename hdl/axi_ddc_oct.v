`timescale 1 ns / 1 ps

module axi_ddc_oct #
(
    parameter integer C_S00_AXI_DATA_WIDTH = 32,
    parameter integer C_S00_AXI_ADDR_WIDTH = 5,
    parameter integer N_CH = 4
)
(
    input wire s_axis_aclk,
    input wire s_axis_aresetn,

    // ADC I, 8 lanes x (12 + 4(pad)) bits
    input wire [127:0] s_axis_i_tdata,
    output wire        s_axis_i_tready,
    input wire         s_axis_i_tvalid,

    // ADC Q, 8 lanes x (12 + 4(pad)) bits
    input wire [127:0] s_axis_q_tdata,
    output wire        s_axis_q_tready,
    input wire         s_axis_q_tvalid,

    input wire resync,

    // DAC I, 8 lanes x (14 + 2(pad)) bits
    output wire [127:0] m_axis_ddsi_tdata,
    output wire         m_axis_ddsi_tvalid,
    input  wire         m_axis_ddsi_tready,

    // DAC Q, 8 lanes x (14 + 2(pad)) bits
    output wire [127:0] m_axis_ddsq_tdata,
    output wire         m_axis_ddsq_tvalid,
    input  wire         m_axis_ddsq_tready,

    // Oct DDC output [95:48] Q, [47:0] I
    output wire [95:0] m_axis_ddc_tdata,
    output wire        m_axis_ddc_tvalid,
    input wire         m_axis_ddc_tready,

    // Ports of Axi Slave Bus Interface S00_AXI
    input wire  s00_axi_aclk,
    input wire  s00_axi_aresetn,
    input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_awaddr,
    input wire [2 : 0] s00_axi_awprot,
    input wire  s00_axi_awvalid,
    output wire  s00_axi_awready,
    input wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_wdata,
    input wire [(C_S00_AXI_DATA_WIDTH/8)-1 : 0] s00_axi_wstrb,
    input wire  s00_axi_wvalid,
    output wire  s00_axi_wready,
    output wire [1 : 0] s00_axi_bresp,
    output wire  s00_axi_bvalid,
    input wire  s00_axi_bready,
    input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_araddr,
    input wire [2 : 0] s00_axi_arprot,
    input wire  s00_axi_arvalid,
    output wire  s00_axi_arready,
    output wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_rdata,
    output wire [1 : 0] s00_axi_rresp,
    output wire  s00_axi_rvalid,
    input wire  s00_axi_rready
);

    wire [31:0] ch_axi;
    wire [31:0] pinc_axi;
    wire [31:0] poff_axi;
    wire        pvalid_axi;
    wire [31:0] rate_axi;
    wire        resync_soft_axi;

    axi_ddc_oct_core # ( 
        .C_S_AXI_DATA_WIDTH(C_S00_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S00_AXI_ADDR_WIDTH),
    ) axi_ddc_oct_core_inst (
        .S_AXI_ACLK(s00_axi_aclk),
        .S_AXI_ARESETN(s00_axi_aresetn),
        .S_AXI_AWADDR(s00_axi_awaddr),
        .S_AXI_AWPROT(s00_axi_awprot),
        .S_AXI_AWVALID(s00_axi_awvalid),
        .S_AXI_AWREADY(s00_axi_awready),
        .S_AXI_WDATA(s00_axi_wdata),
        .S_AXI_WSTRB(s00_axi_wstrb),
        .S_AXI_WVALID(s00_axi_wvalid),
        .S_AXI_WREADY(s00_axi_wready),
        .S_AXI_BRESP(s00_axi_bresp),
        .S_AXI_BVALID(s00_axi_bvalid),
        .S_AXI_BREADY(s00_axi_bready),
        .S_AXI_ARADDR(s00_axi_araddr),
        .S_AXI_ARPROT(s00_axi_arprot),
        .S_AXI_ARVALID(s00_axi_arvalid),
        .S_AXI_ARREADY(s00_axi_arready),
        .S_AXI_RDATA(s00_axi_rdata),
        .S_AXI_RRESP(s00_axi_rresp),
        .S_AXI_RVALID(s00_axi_rvalid),
        .S_AXI_RREADY(s00_axi_rready),
        .ch(ch_axi),
        .pinc(pinc_axi),
        .poff(poff_axi),
        .pvalid(pvalid_axi),
        .rate(rate_axi),
        .resync_soft(resync_soft_axi)
    );
 

    /////////////////////////////////////////////////////////////////// User logic
    // Connection between modules
    localparam N_CH_WIDTH = $clog2(N_CH);
    localparam N_CH_C = 2**N_CH_WIDTH;
    localparam DDC_WIDTH = 32; // DDC width
    localparam ACC_WIDTH = 48; // Accumulator width
    localparam DDS_WIDTH = 128; // DDS width

    localparam PINC_WIDTH = 32;
    localparam POFF_WIDTH = 32;

    wire [DDC_WIDTH*2-1:0] ddc_out [0:N_CH-1];
    wire [DDS_WIDTH-1:0]   ddsi_out [0:N_CH-1];
    wire [DDS_WIDTH-1:0]   ddsq_out [0:N_CH-1];
    wire [ACC_WIDTH*2-1:0] acc_out [0:N_CH-1];
    reg  [ACC_WIDTH*2-1:0] acc_out_buf [0:N_CH-1];

    wire [N_CH-1:0] valid_ddc;
    wire [N_CH-1:0] valid_acc;
    wire [N_CH-1:0] valid_dds;

    // Pipeline
    reg  [ACC_WIDTH*2-1:0] data_pipe_buf;
    reg                    valid_pipe_buf;

    // Buffer to cross clock domain between AXI and data converter.
    // Configuration information such as ch and pinc/poff is clocked by S_AXI
    // while ddc_oct is synchronized to the data converter.
    reg [31:0]           pinc_buff_axi;
    reg [31:0]           poff_buff_axi;
    reg [N_CH_WIDTH-1:0] ch_buff_axi;

    always @(posedge s00_axi_aclk) begin
        if (pvalid_axi) begin
            pinc_buff_axi <= pinc_axi;
            poff_buff_axi <= poff_axi;
            ch_buff_axi   <= ch_axi;
        end else begin
            pinc_buff_axi <= pinc_buff_axi;
            poff_buff_axi <= poff_buff_axi;
            ch_buff_axi <= ch_axi;
        end
    end

    // handshake signal
    reg reconf;     // driven by AXI.
    reg reconf_fin; // driven by data converter.
    reg reconf_fin_buf;

    always @(posedge s00_axi_aclk) begin
        if (s00_axi_aresetn == 1'b0) begin
            reconf <= 1'b0;
        end else begin
            if (pvalid_axi) begin
                reconf <= 1'b1;
            end else if (reconf_fin) begin
                reconf <= 1'b0;
            end else begin
                reconf <= reconf;
            end
        end
    end

    always @(posedge s_axis_aclk) begin
        if (s_axis_aresetn == 1'b0) begin
            reconf_fin <= 1'b0;
        end else begin
            if (reconf) begin
                reconf_fin <= 1'b1;
            end else begin
                reconf_fin <= 1'b0;
            end
        end
    end

    // pinc/poff configuration
    always @(posedge s_axis_aclk) begin
        reconf_fin_buf <= reconf_fin;
    end

    // First 1 cycle of reconf_fin
    wire pvalid_dev = (reconf_fin == 1'b1) & (reconf_fin_buf == 1'b0);

    reg [PINC_WIDTH-1:0] pinc_buff [0:N_CH-1];
    reg [POFF_WIDTH-1:0] poff_buff [0:N_CH-1];

    // pinc/poff registration
    always @(posedge s_axis_aclk) begin
        if (pvalid_dev) begin
            pinc_buff[ch_buff_axi] <= pinc_buff_axi;
            poff_buff[ch_buff_axi] <= poff_buff_axi;
        end else begin

        end
    end    

    // Accumulation length
    reg [31:0] acc_len;

    always @(posedge s_axis_aclk) begin
        acc_len <= rate_axi;
    end

    // Software resync
    reg [1:0] resync_soft_buf;
    always @(posedge s_axis_aclk) begin
        resync_soft_buf <= {resync_soft_buf[0], resync_soft_axi};
    end
    wire resync_soft = (resync_soft_buf == 2'b01);

    // Module generation
    genvar i;
    generate
        for(i=0;i<N_CH;i=i+1) begin:ddc_accm
            ddc_oct ddc_oct_inst(
                .s_axis_aclk(s_axis_aclk),
                .s_axis_i_tdata(s_axis_i_tdata),
                .s_axis_i_tready(s_axis_i_tready),
                .s_axis_i_tvalid(s_axis_i_tvalid),
                .s_axis_q_tdata(s_axis_q_tdata),
                .s_axis_q_tready(s_axis_q_tready),
                .s_axis_q_tvalid(s_axis_q_tvalid),
                .s_axis_phase_tdata({poff_buf[i], pinc_buff[i]}),
                .s_axis_phase_tvalid(1'b1),
                .resync(resync | resync_soft),

                .m_axis_ddsi_tdata(ddsi_out[i]),
                .m_axis_ddsi_tvalid(valid_dds[i]),
                .m_axis_ddsi_tready(1'b1),
                .m_axis_ddsq_tdata(ddsq_out[i]),
                .m_axis_ddsq_tvalid(),
                .m_axis_ddsq_tready(1'b1),

                .m_axis_ddc_tdata(ddc_out[i]),
                .m_axis_ddc_tvalid(valid_ddc[i]),
                .m_axis_ddc_tready(1'b1)
            );

            accumulator accum_inst_i(
                .clk(s_axis_aclk),
                .rst(s_axis_aresetn),
                .valid_in(valid_ddc[i]),
                .length(acc_len),
                .data_in(ddc_out[i][DDC_WIDTH-1:0]),
                .valid_out(valid_acc[i]),
                .data_out(acc_out[i][ACC_WIDTH-1:0])
            );

            accumulator accum_inst_q(
                .clk(dev_clk),
                .rst(dev_rst),
                .valid_in(valid_ddc[i]),
                .length(acc_len),
                .data_in(ddc_out[i][32+DDC_WIDTH-1:32]),
                .data_out(acc_out[i][48+ACC_WIDTH-1:48])
            );
        end
    endgenerate

    // Sequentialize
    integer j;
    always @(posedge s_axis_aclk) begin
        if (valid_acc[0]) begin
            for (j=0; j < N_CH; j = j+1) begin
                acc_out_buf[j] <= acc_out[j];
            end
        end
    end

    reg [N_CH_WIDTH-1:0] ch_cnt;
    reg valid_seq;
    wire fin_seq;

    always @(posedge s_axis_aclk) begin
        if (valid_acc[0]) begin
            valid_seq <= 1;
        end else if (fin_seq) begin
            valid_seq <= 0;
        end
    end

    assign fin_seq = (ch_cnt == (N_CH - 1));

    always @(posedge s_axis_aclk) begin
        if (valid_acc[0]) begin
            ch_cnt <= 0;
        end else if (valid_seq) begin
            ch_cnt <= ch_cnt + 1;
        end else begin
            ch_cnt <= 0;
        end
    end

    always @(posedge s_axis_aclk) begin
        data_pipe_buf <= acc_out_buf[ch_cnt];
    end

    assign m_axis_ddc_tdata = data_pipe_buf;

    always @(posedge s_axis_aclk) begin
        valid_pipe_buf <= valid_seq;
    end

    assign m_axis_ddc_tvalid = valid_pipe_buf;


    //////////////////////////////////////////////////////// DDS adder
    wire [DDS_WIDTH-1:0] dds_buf_i [0:2*N_CH_C-2];
    wire [DDS_WIDTH-1:0] dds_buf_q [0:2*N_CH_C-2];

    // dds_buf[0] to dds_buf[N-1] stores raw output from ddc cores
    integer s;
    for (s=0;s<N_CH;s=s+1) begin:dds_buffering
        assign dds_buf_i[s] = ddsi_out[s];
        assign dds_buf_q[s] = ddsq_out[s];
    end

    // l=0: dds_buf[0] = dds_buf[1] + dds_buf[2]
    // l=1: dds_buf[1] = dds_buf[3] + dds_buf[4], dds_buf[2] = dds_buf[5] + dds_buf[6]
    // l=2: dds_buf[3] = dds_buf[7] + dds_buf[8], ... dds_buf[6] = dds_buf[13] + dds_buf[14]
    // l=3: dds_buf[7] = ...

    genvar l, m, n;
    generate
        for(l=0;l<N_CH_WIDTH;l=l+1) begin:kaisen
            for(m=0;m<(2**l);m=m+1) begin:siai
                for(n=0;n<8;n=n+1) begin:lane
                    adder_dds adder_ddsi_inst(
                        .clk(s_axis_aclk),
                        .a( dds_buf_i[2**(l+1) - 1 + 2*m    ][16*(n+1)-1:16*n]),
                        .b( dds_buf_i[2**(l+1) - 1 + 2*m + 1][16*(n+1)-1:16*n]),
                        .s({dds_buf_i[2**l     - 1 +   m    ][16*(n+1)-2:16*n], z})
                    );
                    adder_dds adder_ddsq_inst(
                        .clk(s_axis_aclk),
                        .a( dds_buf_q[2**(l+1) - 1 + 2*m    ][16*(n+1)-1:16*n]),
                        .b( dds_buf_q[2**(l+1) - 1 + 2*m + 1][16*(n+1)-1:16*n]),
                        .s({dds_buf_q[2**l     - 1 +   m    ][16*(n+1)-2:16*n], z})
                    );
                end
            end
        end
    endgenerate

    integer p;
    for(p=0;p<N_CH;p=p+1) begin:first
        assign dds_buf_i[N_CH_C + p][DDS_WIDTH-1:0] = ddsi_out[p];
        assign dds_buf_q[N_CH_C + p][DDS_WIDTH-1:0] = ddsq_out[p];
    end

endmodule
