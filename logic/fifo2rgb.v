module fifo2rgb #(parameter
  HLINES   = 800,
  VLINES   = 480,
  RGB_BITS = 24, // RGB data bits. 16: RGB565, 24: RGB888
  DCLK_DIV = 4,  // Clock divider. Must be even. Minimum supported: 4
  VPW      = 4,  // VSYNC pulse width
  VBP      = 4,  // VSYNC back porch
  VFP      = 8,  // VSYNC front porch
  HPW      = 4,  // HSYNC pulse width
  HBP      = 4,  // HSYNC back porch
  HFP      = 8,  // HSYNC front porch
  VDPOL    = 1,  // VSYNC polarity. 0: Positive, 1: Negative.
  HDPOL    = 1,  // HSYNC polarity. 0: Positive, 1: Negative.
  DCLKPOL  = 1   // DCLK  polarity. 0: Positive, 1: Negative.
) (
  input reset,

  input             data_fifo_wrclk,
  input             data_fifo_rdclk,
  input             data_fifo_wrreq,
  input      [31:0] data_fifo_data,
  output            data_fifo_half_full,

  output reg                rgb_hsync,
  output reg                rgb_vsync,
  output reg                rgb_de,
  output reg                rgb_dclk,
  output reg [RGB_BITS-1:0] rgb_data
);

parameter RGB_BYTES = RGB_BITS / 8;

parameter HPERIOD = HLINES + HPW + HBP + HFP;
parameter VPERIOD = VLINES + VPW + VBP + VFP;

parameter RGB_IDLE = 0;
parameter RGB_SYNC = 1;
parameter RGB_BP   = 2; // Back porch
parameter RGB_DATA = 3;
parameter RGB_FP   = 4; // Front porch

reg [3:0] h_curstate;
reg [3:0] v_curstate;

reg [$clog2(HPERIOD)-1:0] h_cnt;
reg [$clog2(VPERIOD)-1:0] v_cnt;

reg [$clog2(DCLK_DIV)-1:0] dclk_div;

reg [RGB_BITS-1:0] rgb_regs;

wire dclk_pulse0 = dclk_div == 0;

parameter DATA_FIFO_WIDTH = 32;
parameter DATA_FIFO_WIDTH_R = 8;
parameter DATA_FIFO_RATIO = DATA_FIFO_WIDTH / DATA_FIFO_WIDTH_R;
parameter DATA_FIFO_DEPTH_BITS = 8; // 1 block RAM
parameter DATA_FIFO_DEPTH_BITS_R = DATA_FIFO_DEPTH_BITS + $clog2(DATA_FIFO_RATIO);
parameter DATA_FIFO_DEPTH = (1 << DATA_FIFO_DEPTH_BITS);

wire [DATA_FIFO_WIDTH_R-1:0] data_fifo_q;
wire data_fifo_rdempty;
wire data_fifo_wrfull; // Not used. New fifo writes will come only when half full flag is false, and will be 16 * 4 = 64 words at the most.
wire data_fifo_rdreq = !data_fifo_rdempty && (v_curstate == RGB_DATA) && (h_curstate == RGB_DATA) && (dclk_div > 0 && dclk_div <= RGB_BYTES);
wire [DATA_FIFO_DEPTH_BITS-1:0] data_fifo_wrusedw;
assign data_fifo_half_full = data_fifo_wrusedw[DATA_FIFO_DEPTH_BITS-1];

// Data FIFO. Read data (8 bit) to drive RGB.
`ifdef ALTA_SYN
data_fifo u_data_fifo(
  .WrClk  (data_fifo_wrclk  ),
  .WrRstn (!reset           ),
  .RdClk  (data_fifo_rdclk  ),
  .RdRstn (!reset           ),
  .WrReq  (data_fifo_wrreq  ),
  .RdReq  (data_fifo_rdreq  ),
  .WrData (data_fifo_data   ),
  .WrEmpty(                 ),
  .WrFull (data_fifo_wrfull ),
  .WrUsedw(data_fifo_wrusedw),
  .RdEmpty(data_fifo_rdempty),
  .RdFull (                 ),
  .RdUsedw(                 ),
  .RdData (data_fifo_q      )
);
`else
dcfifo_mixed_widths	data_fifo (
  .wrclk    (data_fifo_wrclk  ),
  .wrreq    (data_fifo_wrreq  ),
  .data     (data_fifo_data   ),
  .rdclk    (data_fifo_rdclk  ),
  .rdreq    (data_fifo_rdreq  ),
  .q        (data_fifo_q      ),
  .rdempty  (data_fifo_rdempty),
  .wrfull   (data_fifo_wrfull ),
  .aclr     (reset            ),
`ifdef DCFIFO_HAS_ECC
  .eccstatus(                 ),
`endif
  .rdfull   (                 ),
  .rdusedw  (                 ),
  .wrempty  (                 ),
  .wrusedw  (data_fifo_wrusedw)
);
defparam
  data_fifo.intended_device_family = "Cyclone IV E",
  data_fifo.lpm_numwords = DATA_FIFO_DEPTH,
  data_fifo.lpm_widthu = DATA_FIFO_DEPTH_BITS,
  data_fifo.lpm_widthu_r = DATA_FIFO_DEPTH_BITS_R,
  data_fifo.lpm_showahead = "ON",
  data_fifo.lpm_type = "dcfifo_mixed_widths",
  data_fifo.lpm_width = DATA_FIFO_WIDTH,
  data_fifo.lpm_width_r = DATA_FIFO_WIDTH_R,
  data_fifo.overflow_checking = "OFF",
  data_fifo.rdsync_delaypipe = 3,
  data_fifo.underflow_checking = "OFF",
  data_fifo.use_eab = "ON",
  data_fifo.wrsync_delaypipe = 3;
`endif

wire rgb_clk = data_fifo_rdclk;

// DCLK divider.
always @ (posedge rgb_clk or posedge reset) begin
  if (reset) begin
    dclk_div <= 0;
  end else if (dclk_div == DCLK_DIV - 1) begin
    dclk_div <= 0;
  end else begin
    dclk_div <= dclk_div + 1;
  end
end

// State machine for vertical scan.
always @ (posedge rgb_clk or posedge reset) begin
  if (reset) begin
    v_curstate <= RGB_IDLE;
  end else if (dclk_pulse0) begin
    case (v_curstate)
      RGB_IDLE: if (!data_fifo_rdempty) v_curstate <= RGB_SYNC;
      RGB_SYNC: if (v_cnt == VPW - 1 && h_cnt == HPERIOD - 1) v_curstate <= RGB_BP;
      RGB_BP:   if (v_cnt == VPW + VBP - 1 && h_cnt == HPERIOD - 1) v_curstate <= RGB_DATA;
      RGB_DATA: if (v_cnt == VPW + VBP + VLINES - 1 && h_curstate == RGB_FP && h_cnt == HPERIOD - 1) v_curstate <= RGB_FP;
      RGB_FP:   if (v_cnt == VPERIOD - 1 && h_cnt == HPERIOD - 1) v_curstate <= RGB_IDLE;
    endcase
  end
end

// State machine for horizontal scan.
always @ (posedge rgb_clk or posedge reset) begin
  if (reset) begin
    h_curstate <= RGB_IDLE;
  end else if (dclk_pulse0) begin
    case (h_curstate)
      RGB_IDLE: if (!data_fifo_rdempty) h_curstate <= RGB_SYNC;
      RGB_SYNC: if (h_cnt == HPW - 1) h_curstate <= RGB_BP;
      RGB_BP:   if (h_cnt == HPW + HBP - 1) h_curstate <= RGB_DATA;
      RGB_DATA: if (h_cnt == HPW + HBP + HLINES - 1) h_curstate <= RGB_FP;
      RGB_FP:   if (h_cnt == HPERIOD - 1) h_curstate <= v_cnt == VPW + VBP + VLINES + VFP - 1 ? RGB_IDLE : RGB_SYNC;
    endcase
  end
end

// Vertical scan counter.
always @ (posedge rgb_clk or posedge reset) begin
  if (reset) begin
    v_cnt <= 0;
  end else if (v_curstate != RGB_IDLE && dclk_pulse0 && h_cnt == HPERIOD - 1) begin
    v_cnt <= v_cnt == VPERIOD - 1 ? 0 : v_cnt + 1;
  end
end

// Horizontal scan counter.
always @ (posedge rgb_clk or posedge reset) begin
  if (reset) begin
    h_cnt <= 0;
  end else if (v_curstate != RGB_IDLE && dclk_pulse0) begin
    h_cnt <= h_cnt == HPERIOD - 1 ? 0 : h_cnt + 1;
  end
end

// Shift register from data fifo. 8 bits at a time.
always @ (posedge rgb_clk or posedge reset) begin
  if (reset) begin
    rgb_regs <= 0;
  end else if (h_curstate == RGB_DATA && dclk_div > 0 && dclk_div <= RGB_BYTES) begin
    rgb_regs <= { data_fifo_q, rgb_regs[RGB_BITS-1:8] };
  end
end

// Actual RGB data synced to DCLK.
always @ (posedge rgb_clk or posedge reset) begin
  if (reset) begin
    rgb_data <= 0;
  end else if (h_curstate == RGB_DATA && dclk_pulse0) begin
    rgb_data <= rgb_regs;
  end
end

// DCLK, DE, HSYCN, and VSYNC. Based on state machines and polarity settings.
always @ (posedge rgb_clk or posedge reset) begin
  if (reset) begin
    rgb_dclk  <= !DCLKPOL;
    rgb_de    <= 1'b0;
    rgb_vsync <= VDPOL;
    rgb_hsync <= HDPOL;
  end else begin
    if (dclk_pulse0) begin
      rgb_dclk <= DCLKPOL;
    end else if (dclk_div == DCLK_DIV / 2) begin
      rgb_dclk <= !DCLKPOL;
    end
    if (dclk_pulse0) begin
      rgb_de    <= (v_curstate == RGB_DATA) && (h_curstate == RGB_DATA);
      rgb_vsync <= (v_curstate == RGB_SYNC) ^ VDPOL;
      rgb_hsync <= (h_curstate == RGB_SYNC) ^ HDPOL;
    end
  end
end

endmodule
