`timescale 1 ns / 1 ps

module axi_ddc_daq2 #
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

    // Oct DDC output [61:32] Q, [29:0] I
    output wire [63:0] m_axis_ddc_tdata,
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

    axi_ddc_daq2_core # ( 
        .C_S_AXI_DATA_WIDTH(C_S00_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S00_AXI_ADDR_WIDTH),
    ) axi_ddc_daq2_core_inst (
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
    localparam DDC_WIDTH = 32 // DDC width
    localparam ACC_WIDTH = 48 // Accumulator width

    wire [DDC_WIDTH*2-1:0] ddc_out [0:N_CH-1];
    wire [ACC_WIDTH*2-1:0] acc_out [0:N_CH-1];
    reg  [ACC_WIDTH*2-1:0] acc_out_buf [0:N_CH-1];
    wire [N_CH-1:0] valid_ddc;
    wire [N_CH-1:0] valid_acc;

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
    reg reconf_start;
    reg reconf_fin; // driven by data converter.

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
                if (reconf_start == 1'b0) begin
                    reconf_start <= 1'b1;
                end else begin
                    reconf_start <= 1'b0;
                    reconf_fin <= 1'b1;
                end
            end
        end
    end


    wire wr_ch_axi;
    assign wr_ch_axi = (axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 0);
    reg busy_ch_axi;
    reg busy_ch;
    reg [1:0] busy_buf;
    wire config_strb;
    wire config_fin;
    reg [17:0] accum_length;


    reg [N_CH_WIDTH-1:0] ch_buf_axi;
    reg [N_CH_WIDTH-1:0] ch_buf;
    reg [19:0] poff_buf;
    reg [19:0] pinc_buf;
    

    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            busy_ch_axi <= 1'b0;
            ch_buf_axi <= 1'b0;
        end else begin
            if (wr_ch_axi && slv_reg_wren) begin
                busy_ch_axi <= 1'b1;
                ch_buf_axi <= S_AXI_WDATA[N_CH_WIDTH-1:0];
            end else begin
                if (config_fin) begin
                    busy_ch_axi <= 1'b0;
                end
            end
        end
    end

    assign user_wbusy = busy_ch_axi;

    // AXI to dev clk buffer
    always @(posedge dev_clk) begin
        ch_buf <= ch_buf_axi;
        pinc_buf <= slv_reg1[19:0];
        poff_buf <= slv_reg2[19:0];
        busy_ch <= busy_ch_axi;
    end

    always @(posedge dev_clk) begin
        busy_buf <= {busy_buf[0], busy_ch};
    end
    assign config_strb = (busy_buf == 2'b01);
    assign config_fin = (busy_buf == 2'b11);


    // Address 3: Accumulation length

    always @(posedge dev_clk) begin
        accum_length <= slv_reg3[17:0];
    end

    // Address 4: software resync
    reg [1:0] resync_soft_buf;
    wire resync_soft;
    always @(posedge dev_clk) begin
        resync_soft_buf <= {resync_soft_buf[0], resync_soft_axi};
    end
    assign resync_soft = (resync_soft_buf == 2'b01);

    // Module generation

    genvar i;
    generate
        for(i=0;i<N_CH;i=i+1) begin:ddc_accm
            ddc_quad ddc_quad_inst(
                .clk(dev_clk),
                .data_in_0(data_in_0),
                .data_in_1(data_in_1),
                .data_in_2(data_in_2),
                .data_in_3(data_in_3),
                .pinc(pinc_buf),
                .poff(poff_buf),
                .p_valid(config_strb & (ch_buf == i)),
                .resync(resync | resync_soft),
                .valid_out(valid_ddc[i]),
                .data_out(ddc_out[i])
            );

            accumulator accum_inst_i(
                .clk(dev_clk),
                .rst(dev_rst),
                .valid_in(valid_ddc[i]),
                .length(accum_length),
                .data_in(ddc_out[i][30:0]),
                .valid_out(valid_accum[i]),
                .data_out(accum_out[i][47:0])
            );

            accumulator accum_inst_q(
                .clk(dev_clk),
                .rst(dev_rst),
                .valid_in(valid_ddc[i]),
                .length(accum_length),
                .data_in(ddc_out[i][62:32]),
                .data_out(accum_out[i][95:48])
            );
        end
    endgenerate

    // Sequentialize
    integer j;
    always @(posedge dev_clk) begin
        if (valid_accum[0]) begin
            for (j=0; j < N_CH; j = j+1) begin
                accum_out_buf[j] <= accum_out[j];
            end
        end
    end

    reg [N_CH_WIDTH-1:0] ch_cnt;
    reg valid_seq;
    wire fin_seq;

    always @(posedge dev_clk) begin
        if (valid_accum[0]) begin
            valid_seq <= 1;
        end else if (fin_seq) begin
            valid_seq <= 0;
        end
    end

    assign fin_seq = (ch_cnt == (N_CH - 1));

    always @(posedge dev_clk) begin
        if (valid_accum[0]) begin
            ch_cnt <= 0;
        end else if (valid_seq) begin
            ch_cnt <= ch_cnt + 1;
        end else begin
            ch_cnt <= 0;
        end
    end

    always @(posedge dev_clk) begin
        data_out_buf <= accum_out_buf[ch_cnt];
    end

    assign data_out = data_out_buf;

    always @(posedge dev_clk) begin
        valid_out_buf <= valid_seq;
    end

    assign valid_out = valid_out_buf;


endmodule
