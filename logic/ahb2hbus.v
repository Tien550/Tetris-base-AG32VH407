`timescale 1ns/1ps
module ahb2hbus #(parameter integer
  ADDR_BITS       = 24, // Address in bytes.
  DATA_BITS       = 32, // AHB data width. Can be 32 or 64.
  NUM_DEV         = 2,  // Number of HyperRAM devices.
  ADQ_BITS        = 8,  // ADQ bits in each device
  LATENCY_CNT     = 7   // Supported latencies: 3, 4, 5, 6, 7
) (
  input      reset,
  output reg dma_int,   // DMA interrupt. Active high whenenver DMA is finished.
  output reg dma_running,
  input      dma_ready, // Flag to indicate that a new DMA transfer can be started.

  input                        ahb_clock, // AHB controlled by MCU
  input      [1:0]             ahb_htrans,
  input                        ahb_hready,
  input                        ahb_hwrite,
  input      [ADDR_BITS:0]     ahb_haddr, // 1 extra bit to access registers
  input      [2:0]             ahb_hsize,
  input      [2:0]             ahb_hburst,
  input      [DATA_BITS/8-1:0] ahb_hstrb,
  input      [DATA_BITS-1:0]   ahb_hwdata,
  output reg [DATA_BITS-1:0]   ahb_hrdata,
  output                       ahb_hresp,
  output reg                   ahb_hreadyout,
  output                       ahb_resetn,

  output reg [1:0]             mst_ahb_htrans, // Master AHB driving DMA or other data intensive interface
  output                       mst_ahb_hready,
  output                       mst_ahb_hwrite,
  output reg [31:0]            mst_ahb_haddr,
  output     [2:0]             mst_ahb_hsize,
  output     [2:0]             mst_ahb_hburst,
  output reg [DATA_BITS-1:0]   mst_ahb_hwdata,
  input      [DATA_BITS-1:0]   mst_ahb_hrdata,
  input                        mst_ahb_hresp,
  input                        mst_ahb_hreadyout,

  input                               hbus_clk, // HyperRAM interface
  input                               hbus_clk90,
  inout      [ADQ_BITS*NUM_DEV-1:0]   hbus_adq,
  inout      [ADQ_BITS/8*NUM_DEV-1:0] hbus_rwds,
  output     [NUM_DEV-1:0]            hbus_clk_out,
  output reg [NUM_DEV-1:0]            hbus_csn,
  output     [NUM_DEV-1:0]            hbus_resetn
);
parameter RWDS_BITS = ADQ_BITS / 8;
parameter DATA_RATIO = DATA_BITS / (ADQ_BITS * 2 * NUM_DEV); // Must be an integer
parameter FIFO_SYNC_DELAY = 3;

parameter IN_FIFO_CNT = NUM_DEV * RWDS_BITS;
parameter IN_FIFO_DEPTH_BITS = 10 - NUM_DEV; // 1 block RAM
parameter IN_FIFO_DEPTH_BITS_R = IN_FIFO_DEPTH_BITS - $clog2(DATA_RATIO);
parameter IN_FIFO_DEPTH = (1 << IN_FIFO_DEPTH_BITS);
parameter IN_FIFO_WIDTH = ADQ_BITS * 2 / RWDS_BITS; // 16
parameter IN_FIFO_WIDTH_R = DATA_BITS / IN_FIFO_CNT; // = IN_FIFO_WIDTH * DATA_RATIO;

parameter OUT_FIFO_DEPTH_BITS_R = 10 - NUM_DEV; // 1 block RAM
parameter OUT_FIFO_DEPTH_BITS = OUT_FIFO_DEPTH_BITS_R - $clog2(DATA_RATIO);
parameter OUT_FIFO_DEPTH = (1 << OUT_FIFO_DEPTH_BITS);
parameter OUT_FIFO_WIDTH = DATA_BITS + DATA_BITS / 8;
parameter OUT_FIFO_WIDTH_R = (ADQ_BITS + RWDS_BITS) * NUM_DEV * 2;

parameter HBUS_IDLE    = 0;
parameter HBUS_CA      = 1;
parameter HBUS_LATENCY = 2;
parameter HBUS_WRITE   = 3;
parameter HBUS_READ    = 4;
parameter HBUS_READY   = 5;

parameter DMA_ADDR_BASE = (32'b11 << (ADDR_BITS-1));
parameter DMA_ADDR_CTRL = DMA_ADDR_BASE + 0;
parameter DMA_ADDR_HBUS = DMA_ADDR_BASE + 4;
parameter DMA_ADDR_MST  = DMA_ADDR_BASE + 8;

reg [3:0] dma_burst_cnt;
reg dma_ahb_write;
reg dma_ahb_read;
reg dma_en;
reg dma_write;
reg dma_circ;
reg [1:0] dma_burst;
reg dma_mst_incr;
reg [15:0] dma_size;
reg dma_active;
reg dma_pending;
reg [ADDR_BITS-1:0] dma_hbus_addr;
reg [3:0] dma_ahb_addr;
reg mst_data_phase, mst_data_phase_d;
reg [IN_FIFO_CNT-1:0] dma_fifo_rdreq;
// Launch a HBUS operation every 4 AHB burst
wire dma_hbus_burst = dma_size[1:0] > 0;
reg dma_streaming;

// Shadow registers for circular mode
reg [15:0] dma_size0;
reg [31:0] mst_ahb_haddr0;
reg [ADDR_BITS-1:0] dma_hbus_addr0;

wire [4:0] DMA_BURST = dma_burst == 0 ? 1 : dma_burst == 1 ? 4 : dma_burst == 2 ? 8 : 16;
wire dma_wrreq;
wire dma_rdreq = &dma_fifo_rdreq;
wire is_dma_addr = ahb_haddr[ADDR_BITS-:2] == 2'b11;

reg [2:0] ahb_state, hbus_state;

// burst_type 1: Linear Burst, 0: Wrapped Burst
wire burst_type = (ahb_hburst == 2 || ahb_hburst == 4 || ahb_hburst == 6) ? 1'b0 : 1'b1;

parameter AHB_RESET_DELAY = 7; // Delayed AHB reset for HRAM to recover from standby (tRH)
reg [AHB_RESET_DELAY-1:0] ahb_rstn_reg;
wire ahb_rstn = ahb_rstn_reg[AHB_RESET_DELAY-1];
assign ahb_resetn = ahb_rstn;
assign ahb_hresp = 1'b0;
wire ahb_start = ahb_htrans == 2'b10 && ahb_hreadyout && !ahb_hresp;
wire ahb_hbus = ahb_start && !is_dma_addr;
wire ahb_dma  = ahb_start && is_dma_addr;
reg ahb_running, ahb_running_d;
reg ahb_pending;
reg ahb_trigger, ahb_trigger_d;
reg ahb_seq0, ahb_seq;
reg ahb_data_wr;
reg ahb_wait_rd;
reg ahb_pause_rd;
wire ahb_begin = (ahb_hbus || ahb_running) && !ahb_running_d || dma_pending && !ahb_running_d;

wire dma_active_ready = dma_active && dma_ready;
wire dma_pause_fifo = dma_streaming && ahb_state == HBUS_IDLE && ahb_running_d && !(mst_ahb_htrans[1] && mst_ahb_hreadyout);
wire dma_stop = !dma_active && dma_burst_cnt == 0 && mst_ahb_hreadyout;

reg [47:0] ca_ahb;
reg [47:0] ahb_ca;
wire [31:0] sys_word_addr = ahb_haddr[ADDR_BITS-1:RWDS_BITS*NUM_DEV];
wire [31:0] dma_word_addr = dma_hbus_addr[ADDR_BITS-1:RWDS_BITS*NUM_DEV];
wire ahb_ca_rd_wrn = ahb_ca[47];
wire ahb_ca_reg_memn = ahb_ca[46];
wire [47:0] ca_ahb_val = { !ahb_hwrite, ahb_haddr[ADDR_BITS], burst_type, sys_word_addr[31:3], 13'h0, sys_word_addr[2:0] };
wire [47:0] ca_dma_val = { !dma_write, 1'b0, 1'b1, dma_word_addr[31:3], 13'h0, dma_word_addr[2:0] };
reg  [2:0] hsize;
wire [DATA_BITS/8-1:0] hstrb = hsize == 0 ? (1'b1 << dma_ahb_addr[1:0]) : hsize == 1 ? (2'b11 << dma_ahb_addr[1:0]) : 4'b1111; // Write byte mask

reg [1:0] hbus_rstn_reg;
reg [47:0] hbus_ca;
reg adq_oe;
reg [NUM_DEV-1:0] adq_out_oe;
reg [NUM_DEV-1:0] clk_oe;
reg [NUM_DEV-1:0] clk_out_oe;
reg [NUM_DEV-1:0] clk_rst;
reg hbus_ca_del;
reg [1:0] hbus_ca_cnt;
reg [3:0] hbus_lat_cnt;
reg [1:0] hbus_data_cnt;
reg hbus_running;
reg hbus_ca_rd_wrn;
reg hbus_ca_reg_memn;
reg hbus_seq;
reg hbus_add_lat;
reg hbus_add_lat_d;
wire rwds_oe = !hbus_ca_rd_wrn && !hbus_ca_reg_memn && (hbus_state == HBUS_WRITE || hbus_state == HBUS_IDLE);
wire hbus_rstn = hbus_rstn_reg[1];

reg  [OUT_FIFO_WIDTH-1:0] out_fifo_data;
wire [(ADQ_BITS+RWDS_BITS)*NUM_DEV*2-1:0] out_fifo_q;
reg  out_fifo_wrreq;
wire out_fifo_wrempty;
wire out_fifo_rdempty;
reg  out_fifo_rdreq_reg;
wire out_fifo_rdreq = !out_fifo_rdempty && out_fifo_rdreq_reg;
wire [OUT_FIFO_DEPTH_BITS-1:0] out_fifo_wrusedw;
reg  out_fifo_half_full_reg;

reg  [IN_FIFO_CNT-1:0] in_fifo_reset;
wire [IN_FIFO_CNT-1:0] in_fifo_wrclk;
reg  [IN_FIFO_CNT-1:0] in_fifo_wrreq;
reg  [IN_FIFO_CNT-1:0] in_fifo_wrreq_rst;
wire [IN_FIFO_CNT-1:0] in_fifo_rdempty;
wire [IN_FIFO_CNT-1:0] in_fifo_rdreq;
wire [IN_FIFO_CNT-1:0] in_fifo_half_full;
reg  in_fifo_rden;
(* keep = 1 *) reg  in_fifo_half_full_reg;
wire [ADQ_BITS*2*NUM_DEV-1:0] in_fifo_data;
wire [IN_FIFO_WIDTH_R-1:0] in_fifo_q[IN_FIFO_CNT];

reg  [ADQ_BITS-1:0] adq_out_h[NUM_DEV];
reg  [ADQ_BITS-1:0] adq_out_l[NUM_DEV];
wire [ADQ_BITS-1:0] adq_in_h[NUM_DEV];
wire [ADQ_BITS-1:0] adq_in_l[NUM_DEV];

reg [RWDS_BITS-1:0] rwds_h[NUM_DEV];
reg [RWDS_BITS-1:0] rwds_l[NUM_DEV];
reg [NUM_DEV-1:0]   rwds_out_oe;

reg  [RWDS_BITS*NUM_DEV-1:0] rwds_reg;
wire [RWDS_BITS*NUM_DEV-1:0] rwds_in;
wire rwds_2x_latency = |rwds_reg;
wire hbus_extend_latency = hbus_add_lat && !hbus_add_lat_d && rwds_2x_latency;
reg hbus_lat_ending_reg ;
wire hbus_lat_ending = LATENCY_CNT >= 5 ? hbus_lat_ending_reg : hbus_lat_cnt == 0 || (hbus_lat_cnt == 4'he && LATENCY_CNT == 3 && !hbus_extend_latency);

wire [DATA_BITS-1:0] hbus_hrdata;

assign mst_ahb_hready = mst_ahb_hreadyout;
assign mst_ahb_hwrite = !dma_write;
assign mst_ahb_hsize  = DATA_BITS == 32 ? 3'b010 : 3'b011; // WORD/DWORD access
assign mst_ahb_hburst = {dma_burst, 1'b1}; // INCR/INCR4/INCR8/INCR16

assign dma_wrreq = mst_data_phase && mst_ahb_hreadyout && dma_write;

// Output FIFO. Write from ahb_clock domain and read from hbus_clk domain.
`ifdef ALTA_SYN
out_fifo u_out_fifo(
  .WrClk  (ahb_clock       ),
  .WrRstn (ahb_rstn        ),
  .RdClk  (hbus_clk        ),
  .RdRstn (ahb_rstn        ),
  .WrReq  (out_fifo_wrreq  ),
  .RdReq  (out_fifo_rdreq  ),
  .WrData (out_fifo_data   ),
  .WrEmpty(                ),
  .WrFull (                ),
  .WrUsedw(out_fifo_wrusedw),
  .RdEmpty(out_fifo_rdempty),
  .RdFull (                ),
  .RdUsedw(                ),
  .RdData (out_fifo_q      )
);
`else
dcfifo_mixed_widths	out_fifo (
  .wrclk    (ahb_clock       ),
  .wrreq    (out_fifo_wrreq  ),
  .data     (out_fifo_data   ),
  .rdclk    (hbus_clk        ),
  .rdreq    (out_fifo_rdreq  ),
  .q        (out_fifo_q      ),
  .rdempty  (out_fifo_rdempty),
  .wrfull   (                ),
  .aclr     (!ahb_rstn       ),
`ifdef DCFIFO_HAS_ECC
  .eccstatus(                ),
`endif
  .rdfull   (                ),
  .rdusedw  (                ),
  .wrempty  (out_fifo_wrempty),
  .wrusedw  (out_fifo_wrusedw)
);
defparam
  out_fifo.intended_device_family = "Cyclone IV E",
  out_fifo.lpm_numwords = OUT_FIFO_DEPTH,
  out_fifo.lpm_widthu = OUT_FIFO_DEPTH_BITS,
  out_fifo.lpm_widthu_r = OUT_FIFO_DEPTH_BITS_R,
  out_fifo.lpm_showahead = "OFF",
  out_fifo.lpm_type = "dcfifo_mixed_widths",
  out_fifo.lpm_width = OUT_FIFO_WIDTH,
  out_fifo.lpm_width_r = OUT_FIFO_WIDTH_R,
  out_fifo.overflow_checking = "OFF",
  out_fifo.rdsync_delaypipe = FIFO_SYNC_DELAY + 2,
  out_fifo.underflow_checking = "OFF",
  out_fifo.use_eab = "ON",
  out_fifo.wrsync_delaypipe = FIFO_SYNC_DELAY + 2;
`endif

genvar grp_idx;
generate
// Group data into 18 bits for every RWDS
for (grp_idx = 0; grp_idx < DATA_BITS / 16; grp_idx = grp_idx + 1) begin : gen_ahb_fifo
  always @ (posedge ahb_clock) begin
    out_fifo_data[grp_idx*18+:18] <= dma_streaming ? {{DATA_BITS/8{1'b1}}, mst_ahb_hrdata[grp_idx*16+:16]} : {ahb_hstrb[grp_idx*2+:2] & hstrb[grp_idx*2+:2], ahb_hwdata[grp_idx*16+:16]};
  end
  assign hbus_hrdata[grp_idx*16+:16] = in_fifo_q[grp_idx%IN_FIFO_CNT][grp_idx/IN_FIFO_CNT*16+:16];
end
endgenerate

always @ (posedge ahb_clock) begin
  out_fifo_wrreq <= dma_streaming ? dma_wrreq : (ahb_state == HBUS_WRITE && ahb_hreadyout && ahb_data_wr);
end

always @(posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    out_fifo_half_full_reg <= 1'b0;
  end else begin
    out_fifo_half_full_reg <= out_fifo_wrusedw[OUT_FIFO_DEPTH_BITS-1];
  end
end

always @ (posedge ahb_clock) begin
  if (dma_ahb_read) begin
    case (dma_ahb_addr)
      DMA_ADDR_CTRL[3:0]: ahb_hrdata <= { dma_size, 7'h0, dma_mst_incr, 2'h0, dma_burst, dma_circ, dma_int, dma_write, dma_running };
    endcase
  end else if (in_fifo_rden) begin
    ahb_hrdata <= hbus_hrdata;
  end
end

genvar f;
generate
for (f = 0; f < IN_FIFO_CNT; f = f + 1) begin : gen_in_fifo
  wire [IN_FIFO_WIDTH-1:0] fifo_data = in_fifo_data[f*IN_FIFO_WIDTH+:IN_FIFO_WIDTH];
  wire [IN_FIFO_DEPTH_BITS_R-1:0] in_fifo_rdusedw;
  reg [IN_FIFO_DEPTH_BITS_R-1:0] rdusedw;

  // Input FIFO. Write from RWDS clock domain and read from ahb_clock domain.
`ifdef ALTA_SYN
  in_fifo u_in_fifo(
    .WrRstn (!(in_fifo_reset[f] & in_fifo_wrreq_rst[f])),
    .RdRstn (!(in_fifo_reset[f] & in_fifo_wrreq_rst[f])),
    .WrClk  (in_fifo_wrclk[f]  ),
    .RdClk  (ahb_clock         ),
    .WrReq  (in_fifo_wrreq[f]  ),
    .RdReq  (in_fifo_rdreq[f]  ),
    .WrData (fifo_data         ),
    .WrEmpty(                  ),
    .WrFull (                  ),
    .WrUsedw(                  ),
    .RdEmpty(in_fifo_rdempty[f]),
    .RdFull (                  ),
    .RdUsedw(in_fifo_rdusedw   ),
    .RdData (in_fifo_q[f]      )
  );
`else
  dcfifo_mixed_widths	in_fifo (
    .wrclk    (in_fifo_wrclk[f]  ),
    .wrreq    (in_fifo_wrreq[f]  ),
    .data     (fifo_data         ),
    .rdclk    (ahb_clock         ),
    .rdreq    (in_fifo_rdreq[f]  ),
    .q        (in_fifo_q[f]      ),
    .rdempty  (in_fifo_rdempty[f]),
    .wrfull   (                  ),
    .aclr     (in_fifo_reset[f] & in_fifo_wrreq_rst[f]),
`ifdef DCFIFO_HAS_ECC
    .eccstatus(                  ),
`endif
    .rdfull   (                  ),
    .rdusedw  (in_fifo_rdusedw   ),
    .wrempty  (                  ),
    .wrusedw  (                  )
  );
  defparam
    in_fifo.intended_device_family = "Cyclone IV E",
    in_fifo.lpm_numwords = IN_FIFO_DEPTH,
    in_fifo.lpm_widthu = IN_FIFO_DEPTH_BITS,
    in_fifo.lpm_widthu_r = IN_FIFO_DEPTH_BITS_R,
    in_fifo.lpm_showahead = "ON",
    in_fifo.lpm_type = "dcfifo_mixed_widths",
    in_fifo.lpm_width = IN_FIFO_WIDTH,
    in_fifo.lpm_width_r = DATA_BITS / IN_FIFO_CNT,
    in_fifo.overflow_checking = "OFF",
    in_fifo.rdsync_delaypipe = FIFO_SYNC_DELAY + 2,
    in_fifo.underflow_checking = "OFF",
    in_fifo.use_eab = "ON",
    in_fifo.wrsync_delaypipe = FIFO_SYNC_DELAY + 2;
`endif

  assign in_fifo_wrclk[f] = !rwds_in[f]; // There could be skew between multiple RWDS pins
  assign in_fifo_rdreq[f] = |in_fifo_rdempty == 0 && !dma_pause_fifo && in_fifo_rden; // Wait for all in_fifo's are non-empty
  assign in_fifo_half_full[f] = in_fifo_rdusedw[IN_FIFO_DEPTH_BITS_R-1];

  always @(posedge ahb_clock or negedge ahb_rstn) begin
    if (!ahb_rstn) begin
      rdusedw <= 0;
    end else begin
      rdusedw <= in_fifo_rdusedw;
    end
  end

  always @(posedge ahb_clock or negedge ahb_rstn) begin
    if (!ahb_rstn) begin
      dma_fifo_rdreq[f] <= 1'b0;
    end else begin
      dma_fifo_rdreq[f] <= dma_streaming && rdusedw > DMA_BURST[4:1];
    end
  end

  // Reset input FIFO and discard all data once a HyperRAM read is done.
  always @(posedge ahb_clock or negedge ahb_rstn) begin
    if (!ahb_rstn) begin
      in_fifo_reset[f] <= 1'b1;
    end else if (!in_fifo_reset[f] && (ahb_state == HBUS_READ || ahb_state == HBUS_IDLE) && ahb_hreadyout || dma_streaming && ahb_state == HBUS_IDLE && ahb_running && !ahb_seq0) begin
      in_fifo_reset[f] <= 1'b1;
    end else if (ahb_ca_rd_wrn && (ahb_trigger || ahb_running && !ahb_running_d) || dma_streaming && ahb_running_d && ahb_seq0) begin
      in_fifo_reset[f] <= 1'b0;
    end
  end

  always @(posedge hbus_clk or negedge hbus_rstn) begin
    if (!hbus_rstn) begin
      in_fifo_wrreq_rst[f] <= 1'b0;
    end else if (hbus_state == HBUS_READY) begin
      in_fifo_wrreq_rst[f] <= 1'b1;
    end else if (hbus_state == HBUS_READ) begin
      in_fifo_wrreq_rst[f] <= 1'b0;
    end
  end

  always @(posedge in_fifo_wrclk[f] or posedge in_fifo_wrreq_rst[f]) begin
    if (in_fifo_wrreq_rst[f]) begin
      in_fifo_wrreq[f] <= 1'b0;
    end else begin
      in_fifo_wrreq[f] <= 1'b1;
    end
  end
end
endgenerate

always @(posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    in_fifo_rden <= 1'b0;
  end else if (ahb_htrans[1] && !ahb_hwrite && (ahb_hreadyout && !ahb_pause_rd || &in_fifo_rdreq) || ahb_wait_rd && ahb_htrans != 2'b01 || dma_streaming) begin
    in_fifo_rden <= 1'b1;
  end else begin
    in_fifo_rden <= 1'b0;
  end
end

always @(posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    in_fifo_half_full_reg <= 1'b0;
  end else begin
    in_fifo_half_full_reg <= |in_fifo_half_full;
  end
end

always @ (posedge ahb_clock or posedge reset) begin
  if (reset) begin
    ahb_rstn_reg <= 0;
  end else if (!ahb_rstn) begin
    ahb_rstn_reg <= ahb_rstn_reg + 1;
  end
end

// Flag to indicate a HyperRAM transfer is ongoing
always @ (posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    ahb_seq0 <= 1'b0;
  end else if (ahb_trigger && !ahb_trigger_d) begin
    ahb_seq0 <= 1'b1;
  end else if (!dma_streaming && (ahb_state == HBUS_READ || ahb_state == HBUS_WRITE) && !ahb_htrans[0] && ahb_hreadyout ||
               dma_streaming && !mst_ahb_htrans[0] && mst_ahb_hreadyout && mst_data_phase && !dma_hbus_burst) begin
    ahb_seq0 <= 1'b0;
  end
end

// Delay ahb_seq0 to account for out fifo latency.
always @ (posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    ahb_seq <= 1'b0;
  end else if (ahb_trigger && !ahb_trigger_d) begin
    ahb_seq <= 1'b1;
  end else if (!out_fifo_wrreq) begin
    ahb_seq <= ahb_seq0;
  end
end

// Cross domain from hbus_clk to ahb_clock

// Trigger to hbus_clk domain to indicate a transfer is started.
always @ (posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    ahb_trigger <= 1'b0;
  end else if (ahb_begin) begin
    ahb_trigger <= 1'b1;
  end else if (hbus_running) begin
    ahb_trigger <= 1'b0;
  end
end

always @ (posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    ahb_trigger_d <= 1'b0;
  end else begin
    ahb_trigger_d <= ahb_trigger;
  end
end

// Transfer running state. Will go low after hbus_running goes low.
always @ (posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    ahb_running <= 1'b0;
  end else if (!hbus_running && ahb_running && ahb_running_d && !ahb_trigger) begin
    ahb_running <= 1'b0;
  end else if (!dma_streaming && (ahb_hbus || ahb_pending) || dma_streaming && !ahb_running_d && mst_ahb_hreadyout) begin
    ahb_running <= 1'b1;
  end
end

// Will go high if a new AHB transfer is initiated before the last one is finished.
always @ (posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    ahb_pending <= 1'b0;
  end else if (ahb_hbus && (ahb_running || ahb_running_d || dma_active_ready)) begin
    ahb_pending <= 1'b1;
  end else if (ahb_state == HBUS_CA) begin
    ahb_pending <= 1'b0;
  end
end

always @ (posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    ahb_running_d <= 1'b0;
  end else begin
    ahb_running_d <= ahb_running;
  end
end

always @ (posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    ahb_data_wr <= 1'b0;
  end else if (ahb_hreadyout && ahb_hwrite) begin
    ahb_data_wr <= ahb_htrans[1];
  end
end

always @ (posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    ahb_wait_rd <= 1'b0;
  end else if (ahb_state == HBUS_CA && ahb_ca_rd_wrn || ahb_state == HBUS_READ && ahb_hreadyout && ahb_htrans[1] && |in_fifo_rdempty) begin
    ahb_wait_rd <= 1'b1;
  end else if (|in_fifo_rdempty == 0) begin
    ahb_wait_rd <= 1'b0;
  end
end

always @ (posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    ahb_pause_rd <= 1'b0;
  end else if (ahb_htrans == 2'b01 && ahb_hreadyout && &in_fifo_rdreq) begin
    // This means an extra read is issued, and in fifo should skip a read next time.
    ahb_pause_rd <= 1'b1;
  end else if (ahb_hreadyout && ahb_htrans[1] && &in_fifo_rdreq == 0) begin
    ahb_pause_rd <= 1'b0;
  end
end

always @ (posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    ahb_hreadyout <= 1'b1;
  end else if (ahb_start) begin
    ahb_hreadyout <= 1'b0;
  end else if (dma_ahb_read || dma_ahb_write) begin // For DMA control and address registers.
    ahb_hreadyout <= 1'b1;
  end else if (ahb_state == HBUS_READ) begin // For HyperRAM read.
    ahb_hreadyout <= &in_fifo_rdreq || ahb_pause_rd || ahb_hreadyout && !ahb_htrans[1];
  end else if (ahb_state == HBUS_WRITE) begin // For HyperRAM write.
    ahb_hreadyout <= !out_fifo_half_full_reg || ahb_htrans != 2'b11;
  end
end

// Save ca and ahb_hsize from AHB address phase.
always @ (posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    ca_ahb <= 48'h0;
    hsize  <= 0;
  end else if (ahb_start) begin
    ca_ahb <= ca_ahb_val;
    hsize  <= ahb_hsize;
  end
end

// Choose the correct ca (command and address) between direct AHB access and DMA.
always @ (posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    ahb_ca <= 48'h0;
  end else if ((dma_pending || dma_active_ready && !ahb_pending) && !ahb_running && (ahb_state == HBUS_IDLE || ahb_state == HBUS_READ)) begin
    ahb_ca <= ca_dma_val;
  end else if (!dma_streaming && !dma_pending) begin
    // Use ca_ahb_val if triggered by ahb_start. Otherwise ahb_ca will be 1 cycle late.
    ahb_ca <= ahb_start ? ca_ahb_val : ca_ahb;
  end
end

// Flag for AHB write to DMA registers.
always @ (posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    dma_ahb_write <= 1'b0;
  end else if (dma_ahb_write) begin
    dma_ahb_write <= 1'b0;
  end else if (ahb_dma && ahb_hwrite) begin
    dma_ahb_write <= 1'b1;
  end
end

// Flag for AHB read to DMA registers.
always @ (posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    dma_ahb_read <= 1'b0;
  end else if (dma_ahb_read) begin
    dma_ahb_read <= 1'b0;
  end else if (ahb_dma && !ahb_hwrite) begin
    dma_ahb_read <= 1'b1;
  end
end

// Address for AHB access to DMA registers.
always @ (posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    dma_ahb_addr <= 0;
  end else if (ahb_start) begin
    dma_ahb_addr <= ahb_haddr;
  end
end

// DMA control registers
always @ (posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    dma_en       <= 1'b0;  // DMA enable.
    dma_write    <= 1'b0;  // DMA write (1) or read (0) from HyperRAM.
    dma_int      <= 1'b0;  // DMA interrupt.
    dma_circ     <= 1'b0;  // DMA circular mode.
    dma_burst    <= 2'b00; // DMA burst size. 0: INCR1, 1: INCR4, 2: INCR8, 3: INCR16.
    dma_mst_incr <= 1'b1;  // Assign to 0 to disable increment of DMA system address.
    dma_size0    <= 0;     // Save dma_size for circular mode.
  end else if (dma_ahb_write && dma_ahb_addr == DMA_ADDR_CTRL[3:0]) begin
    dma_int   <= 1'b0;
    dma_circ  <= ahb_hwdata[3];
    if (ahb_hwdata[0] && !dma_running) begin
      dma_en       <= 1'b1;
      dma_write    <= ahb_hwdata[1];
      dma_burst    <= ahb_hwdata[5:4];
      dma_mst_incr <= ahb_hwdata[5:4] == 0 ? ahb_hwdata[8] : 1'b1; // Only allow non-incr with burst size 1.
      dma_size0    <= ahb_hwdata[31:16];
    end
  end else begin
    if (dma_en) begin
      dma_en <= 1'b0;
    end else if (!dma_running && dma_circ) begin
      dma_en <= 1'b1; // Restart DMA in circular mode.
    end
    if (dma_running && dma_stop) begin
      dma_int <= 1'b1; // Generate interrupt.
    end
  end
end

always @ (posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    dma_size <= 0; // DMA transfer count. Total bytes to transfer = dma_size * burst size
  end else if (dma_en) begin
    dma_size <= dma_size0;
  end else if (dma_running && mst_ahb_htrans == 2'b10) begin
    dma_size <= dma_size - 1;
  end
end

always @ (posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    dma_active <= 1'b0;
  end else begin
    dma_active <= dma_en || dma_size > 0;
  end
end

// Flag to indicate a new DMA transfer is ready to launch.
always @ (posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    dma_pending <= 1'b0;
  end else if (dma_streaming) begin
    dma_pending <= 1'b0;
  end else if (dma_active_ready) begin
    dma_pending <= 1'b1;
  end
end

// DMA is streaming data.
always @ (posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    dma_streaming <= 1'b0;
  end else if (dma_streaming && !ahb_running && ahb_running_d) begin
    dma_streaming <= 1'b0;
  end else if (dma_pending && (!ahb_running || !ahb_running_d) && (ahb_state == HBUS_IDLE || ahb_state == HBUS_READ)) begin
    dma_streaming <= 1'b1;
  end
end

// HyperRAM address used in DMA
always @ (posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    dma_hbus_addr0 <= 0;
  end else if (dma_ahb_write && dma_ahb_addr == DMA_ADDR_HBUS[3:0]) begin
    dma_hbus_addr0 <= { ahb_hwdata[ADDR_BITS-1:2], 2'b00 };
  end
end

always @ (posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    dma_hbus_addr <= 0;
  end else if (dma_en) begin
    dma_hbus_addr <= dma_hbus_addr0;
  end else if (mst_ahb_htrans[1] && mst_ahb_hreadyout) begin
    dma_hbus_addr <= { dma_hbus_addr[ADDR_BITS-1:2] + 1, 2'b00 };
  end
end

// Data phase for master AHB.
always @ (posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    mst_data_phase <= 1'b0;
  end else if (mst_ahb_htrans[1]) begin
    mst_data_phase <= 1'b1;
  end else if (mst_ahb_hreadyout) begin
    mst_data_phase <= 1'b0;
  end
end

always @ (posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    mst_data_phase_d <= 1'b0;
  end else begin
    mst_data_phase_d <= mst_data_phase;
  end
end

// Master AHB system address used in DMA
always @ (posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    mst_ahb_haddr0 <= 0;
  end else if (dma_ahb_write && dma_ahb_addr == DMA_ADDR_MST[3:0]) begin
    mst_ahb_haddr0 <= { ahb_hwdata[31:2], 2'b00 };
  end
end

always @ (posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    mst_ahb_haddr <= 0;
  end else if (dma_en) begin
    mst_ahb_haddr <= mst_ahb_haddr0;
  end else if (mst_ahb_htrans[1] && mst_ahb_hreadyout) begin
    mst_ahb_haddr <= { mst_ahb_haddr[31:2] + dma_mst_incr, 2'b00 };
  end
end

always @ (posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    mst_ahb_hwdata <= 0;
  end else if (&in_fifo_rdreq) begin
    mst_ahb_hwdata <= hbus_hrdata;
  end
end

always @ (posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    dma_running <= 1'b0;
  end else if (dma_en) begin
    dma_running <= 1'b1;
  end else if (dma_stop) begin
    dma_running <= 1'b0;
  end
end

always @ (posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    mst_ahb_htrans <= 2'b00;
  end else if (dma_streaming && mst_ahb_hreadyout) begin
    case (mst_ahb_htrans)
      2'b00: if (!mst_data_phase && (dma_write && (dma_pending || ahb_seq0) || dma_rdreq && ahb_seq0)) mst_ahb_htrans <= 2'b10;
      2'b10: mst_ahb_htrans <= dma_burst == 0 ? 2'b00 : 2'b11;
      2'b11: if (dma_burst_cnt == 1) mst_ahb_htrans <= 2'b00;
    endcase
  end
end

always @ (posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    dma_burst_cnt <= 0;
  end else if (mst_ahb_htrans == 2'b10) begin
    dma_burst_cnt <= DMA_BURST - 1;
  end else if (mst_ahb_htrans == 2'b11 && mst_ahb_hreadyout) begin
    dma_burst_cnt <= dma_burst_cnt - 1;
  end
end

// State machine in ahb_clock domain.
always @ (posedge ahb_clock or negedge ahb_rstn) begin
  if (!ahb_rstn) begin
    ahb_state <= HBUS_IDLE;
  end else begin
    case (ahb_state)
      HBUS_IDLE:
      if (!(dma_pending || dma_streaming) && (ahb_running && !ahb_running_d || !ahb_running && ahb_pending))
          ahb_state <= HBUS_CA;
      HBUS_CA:
        ahb_state <= ahb_ca_rd_wrn ? HBUS_READ : HBUS_WRITE;
      HBUS_READ:
        if (ahb_hreadyout && !ahb_htrans[0])
          ahb_state <= HBUS_IDLE;
      HBUS_WRITE:
        if (ahb_hreadyout && !ahb_htrans[0])
          ahb_state <= HBUS_IDLE;
    endcase
  end
end

always @ (posedge hbus_clk or posedge reset) begin
  if (reset) begin
    hbus_rstn_reg <= 0;
  end else begin
    hbus_rstn_reg <= (hbus_rstn_reg << 1) | 1'b1;
  end
end

// Mask some lower bits of ahb_haddr to always start HyperRAM access at the word boundary. Do it here instead of ahb_ca 
// to achieve better timing.
localparam HADDR_MASK_BITS = $clog2(DATA_BITS/8) - RWDS_BITS * NUM_DEV;
wire [31:0] hbus_ca_mask = 32'hffffffff << (hbus_ca_cnt == 2 && !hbus_ca[46] ? HADDR_MASK_BITS : 0);

// Command and address in hbus_clk domain.
always @(posedge hbus_clk) begin
  if (hbus_running && hbus_state == HBUS_READY) begin
    hbus_ca <= ahb_ca;
  end else if (hbus_state == HBUS_CA) begin
    hbus_ca <= {hbus_ca[31:0] & hbus_ca_mask, hbus_ca[47:32]};
  end
end

always @ (posedge hbus_clk) begin
  if (hbus_state == HBUS_IDLE) begin
    hbus_ca_cnt <= 2;
  end else if (hbus_state == HBUS_CA) begin
    hbus_ca_cnt <= hbus_ca_cnt - 1;
  end
  hbus_ca_del <= (hbus_state == HBUS_CA);
end

// HyperRAM latency count
always @ (posedge hbus_clk) begin
  if (hbus_state == HBUS_CA) begin
    hbus_lat_cnt <= 4'hf;
  end else if (hbus_state == HBUS_LATENCY) begin
    if (hbus_lat_cnt == 4'he) begin
      hbus_lat_cnt <= hbus_extend_latency ? 2 * LATENCY_CNT - 4 : LATENCY_CNT - 4;
    end else begin
      hbus_lat_cnt <= hbus_lat_cnt - 1;
    end
    hbus_add_lat <= 1'b1;
  end else begin
    hbus_add_lat <= 1'b0;
  end
end

always @ (posedge hbus_clk) begin
  hbus_add_lat_d <= hbus_add_lat;
end

always @ (posedge hbus_clk) begin
  hbus_lat_ending_reg <= hbus_lat_cnt == 1;
end

always @ (posedge hbus_clk) begin
  if (hbus_state == HBUS_CA) begin
    // Extra cycle for read to clock input data into fifo.
    hbus_data_cnt <= hbus_ca_rd_wrn ? 1 + DATA_RATIO : 0;
  end else if (hbus_data_cnt > 0 && (hbus_state == HBUS_READ || hbus_state == HBUS_WRITE && adq_oe)) begin
    hbus_data_cnt <= hbus_data_cnt - 1;
  end
end

always @ (posedge hbus_clk or negedge hbus_rstn) begin
  if (!hbus_rstn) begin
    out_fifo_rdreq_reg <= 1'b0;
  end else if (hbus_state == HBUS_LATENCY && hbus_lat_ending) begin
    out_fifo_rdreq_reg <= 1'b1;
  end else if (hbus_state == HBUS_CA) begin
    out_fifo_rdreq_reg <= hbus_ca_reg_memn;
  end
end

// Cross domain from ahb_clock to hbus_clk
always @ (posedge hbus_clk or negedge hbus_rstn) begin
  if (!hbus_rstn) begin
    hbus_running <= 1'b0;
  end else if (ahb_trigger) begin
    hbus_running <= 1'b1;
  end else if (hbus_state == HBUS_IDLE && out_fifo_rdempty && !(|clk_oe) && !(|clk_out_oe)) begin
    hbus_running <= 1'b0;
  end
end

always @ (posedge hbus_clk or negedge hbus_rstn) begin
  if (!hbus_rstn) begin
    hbus_seq <= 1'b0;
  end else if (hbus_running) begin
    hbus_seq <= ahb_seq;
  end
end

always @ (posedge hbus_clk or negedge hbus_rstn) begin
  if (!hbus_rstn) begin
    hbus_ca_rd_wrn   <= 1'b0;
    hbus_ca_reg_memn <= 1'b0;
  end else if (hbus_state == HBUS_CA && hbus_ca_cnt == 2) begin
    hbus_ca_rd_wrn   <= hbus_ca[47];
    hbus_ca_reg_memn <= hbus_ca[46];
  end
end

// State machine in hbus_clk domain
always @ (posedge hbus_clk or negedge hbus_rstn) begin
  if (!hbus_rstn) begin
    hbus_state <= HBUS_IDLE;
  end else begin
    case (hbus_state)
      HBUS_IDLE:
        if (!hbus_running)
          hbus_state <= HBUS_READY;
      HBUS_READY:
        if (hbus_running)
          hbus_state <= HBUS_CA;
      HBUS_CA:
        if (hbus_ca_cnt == 0)
          hbus_state <= (!hbus_ca_rd_wrn && hbus_ca_reg_memn) ? HBUS_WRITE : HBUS_LATENCY;
      HBUS_LATENCY:
        if (hbus_lat_ending)
          hbus_state <= hbus_ca_rd_wrn ? HBUS_READ : HBUS_WRITE;
      HBUS_READ:
        if (hbus_data_cnt == 0 && !hbus_seq)
          hbus_state <= HBUS_IDLE;
      HBUS_WRITE:
        if (hbus_data_cnt == 0 && adq_oe && !hbus_seq)
          hbus_state <= HBUS_IDLE;
    endcase
  end
end

// Output enable for adq
always @(posedge hbus_clk or negedge hbus_rstn) begin
  if (!hbus_rstn) begin
    adq_oe <= 1'b0;
  end else if (hbus_state == HBUS_READY && hbus_running || hbus_state == HBUS_CA && hbus_ca_cnt > 0 || out_fifo_rdreq) begin
    adq_oe <= 1'b1;
  end else begin
    adq_oe <= 1'b0;
  end
end

// Generate DDIO for HyperRAM clock and data.
genvar dev, rwds;
generate
for (dev = 0; dev < NUM_DEV; dev=dev+1) begin : gen_ddio
  assign hbus_resetn[dev] = hbus_rstn;
  assign in_fifo_data[ADQ_BITS*2*dev+ADQ_BITS+:ADQ_BITS] = adq_in_l[dev];
  assign in_fifo_data[ADQ_BITS*2*dev+:ADQ_BITS] = adq_in_h[dev];

  always @(posedge hbus_clk) begin
    // Pause the output clock for those lanes that don't need extra latency (rwds low).
    if (hbus_state != HBUS_LATENCY || hbus_lat_cnt <= LATENCY_CNT - 3) begin
      clk_out_oe[dev] <= clk_oe[dev];
    end else if (hbus_extend_latency) begin
      clk_out_oe[dev] <= rwds_reg[dev*RWDS_BITS];
    end
    adq_out_oe[dev] <= adq_oe;
    rwds_out_oe[dev]<= rwds_oe;
  end

`ifdef ALTA_SYN
  alta_ddio_out #(RWDS_BITS, 1) ddio_rwds (
    .DataInH   (rwds_h[dev]                        ),
    .DataInL   (rwds_l[dev]                        ),
    .OutClk    (hbus_clk                           ),
    .OutClkEn  (1'b1                               ),
    .OutEn     (rwds_out_oe[dev]                   ),
    .AsyncReset(1'b0                               ),
    .SyncReset (1'b0                               ),
    .Pad       (hbus_rwds[dev*RWDS_BITS+:RWDS_BITS])
  );
`else
  altddio_out ddio_rwds (
    .datain_h  (rwds_h[dev]                        ),
    .datain_l  (rwds_l[dev]                        ),
    .outclock  (hbus_clk                           ),
    .oe        (rwds_out_oe[dev]                   ),
    .outclocken(1'b1                               ),
    .aset      (1'b0                               ),
    .aclr      (1'b0                               ),
    .sset      (1'b0                               ),
    .sclr      (1'b0                               ),
    .dataout   (hbus_rwds[dev*RWDS_BITS+:RWDS_BITS]),
    .oe_out    (                                   )
  );
  defparam
    ddio_rwds.width = RWDS_BITS,
    ddio_rwds.power_up_high = "OFF",
    ddio_rwds.intended_device_family = "Cyclone IV E",
    ddio_rwds.oe_reg = "REGISTERED",
    ddio_rwds.extend_oe_disable = "OFF",
    ddio_rwds.invert_output = "OFF";
`endif

  assign rwds_in[dev*RWDS_BITS+:RWDS_BITS] = hbus_rwds[dev*RWDS_BITS+:RWDS_BITS];
  always @ (posedge hbus_clk) begin
    rwds_reg[dev*RWDS_BITS+:RWDS_BITS] <= hbus_rwds[dev*RWDS_BITS+:RWDS_BITS];
  end

  always @(posedge hbus_clk or negedge hbus_rstn) begin
    if (!hbus_rstn) begin
      hbus_csn[dev] <= 1'b1;
    end else if (hbus_state == HBUS_CA) begin
      hbus_csn[dev] <= 1'b0;
    end else if (hbus_state == HBUS_IDLE && !hbus_running) begin
      hbus_csn[dev] <= 1'b1;
    end
  end

  for (rwds = 0; rwds < RWDS_BITS; rwds = rwds + 1) begin : gen_adq
    always @(posedge hbus_clk) begin
      adq_out_h[dev][rwds*8+:8] <= (hbus_state == HBUS_CA || hbus_state == HBUS_LATENCY) ? hbus_ca[47:40] : out_fifo_q[(dev*RWDS_BITS+rwds)*18+8+:8];
      adq_out_l[dev][rwds*8+:8] <= (hbus_state == HBUS_CA || hbus_state == HBUS_LATENCY) ? hbus_ca[39:32] : out_fifo_q[(dev*RWDS_BITS+rwds)*18+0+:8];
      rwds_h[dev][rwds]         <= ~out_fifo_q[(dev*RWDS_BITS+rwds)*18+17];
      rwds_l[dev][rwds]         <= ~out_fifo_q[(dev*RWDS_BITS+rwds)*18+16];
    end
`ifdef ALTA_SYN
    alta_ddio_inout #(8, 1) ddio_adq (
      .DataInH   (adq_out_h[dev][rwds*8+:8]        ),
      .DataInL   (adq_out_l[dev][rwds*8+:8]        ),
      .InClk     (in_fifo_wrclk[dev*RWDS_BITS+rwds]),
      .InClkEn   (1'b1                             ),
      .OutClk    (hbus_clk                         ),
      .OutClkEn  (1'b1                             ),
      .OutEn     (adq_out_oe[dev]                  ),
      .AsyncReset(1'b0                             ),
      .SyncReset (1'b0                             ),
      .DataOutH  (adq_in_h[dev][rwds*8+:8]         ),
      .DataOutL  (adq_in_l[dev][rwds*8+:8]         ),
      .Pad       (hbus_adq[dev*ADQ_BITS+rwds*8+:8] )
    );
`else
    altddio_bidir ddio_adq (
      .padio          (hbus_adq[dev*ADQ_BITS+rwds*8+:8] ),
      .aclr           (1'b0                             ),
      .datain_h       (adq_out_h[dev][rwds*8+:8]        ),
      .datain_l       (adq_out_l[dev][rwds*8+:8]        ),
      .inclock        (in_fifo_wrclk[dev*RWDS_BITS+rwds]),
      .inclocken      (1'b1                             ),
      .oe             (adq_out_oe[dev]                  ),
      .outclock       (hbus_clk                         ),
      .outclocken     (1'b1                             ),
      .dataout_h      (adq_in_h[dev][rwds*8+:8]         ),
      .dataout_l      (adq_in_l[dev][rwds*8+:8]         ),
      .aset           (1'b0                             ),
      .combout        (                                 ),
      .dqsundelayedout(                                 ),
      .oe_out         (                                 ),
      .sclr           (1'b0                             ),
      .sset           (1'b0                             ));
    defparam
      ddio_adq.extend_oe_disable = "OFF",
      ddio_adq.implement_input_in_lcell = "OFF",
      ddio_adq.intended_device_family = "Cyclone IV E",
      ddio_adq.invert_output = "OFF",
      ddio_adq.lpm_hint = "UNUSED",
      ddio_adq.lpm_type = "altddio_bidir",
      ddio_adq.oe_reg = "REGISTERED",
      ddio_adq.power_up_high = "OFF",
      ddio_adq.width = 8;
`endif
  end

  always @(posedge hbus_clk or negedge hbus_rstn) begin
    if (!hbus_rstn) begin
      clk_oe[dev] <= 1'b0;
    end else if (hbus_state == HBUS_LATENCY && hbus_lat_ending && !hbus_ca_rd_wrn && !out_fifo_rdreq) begin
      clk_oe[dev] <= 1'b0;
    end else if (hbus_state == HBUS_READY && hbus_running || hbus_state == HBUS_CA && !(!hbus_ca_rd_wrn && hbus_ca_reg_memn && hbus_ca_cnt == 0)) begin
      clk_oe[dev] <= 1'b1;
    end else if (out_fifo_rdreq && (hbus_state == HBUS_CA || hbus_state == HBUS_WRITE && !(hbus_ca_reg_memn && adq_oe) || // Only 1 clock cycle in reg write data
      hbus_state == HBUS_IDLE) || hbus_state == HBUS_LATENCY || hbus_state == HBUS_READ && !in_fifo_half_full_reg) begin
      clk_oe[dev] <= 1'b1;
    end else begin
      clk_oe[dev] <= 1'b0;
    end
  end

  always @(negedge hbus_clk or negedge hbus_rstn) begin
    if (!hbus_rstn) begin
      clk_rst[dev] <= 1'b1;
    end else begin
      clk_rst[dev] <= !clk_out_oe[dev];
    end
  end

`ifdef ALTA_SYN
  alta_ddio_out #(1, 0) ddio_clk (
    .DataInH   (!clk_rst[dev]    ),
    .DataInL   (1'b0             ),
    .OutClk    (hbus_clk90       ),
    .OutClkEn  (1'b1             ),
    .OutEn     (1'b1             ),
    .AsyncReset(1'b0             ),
    .SyncReset (1'b0             ),
    .Pad       (hbus_clk_out[dev])
  );
`else
  altddio_out ddio_clk (
    .datain_h  (!clk_rst[dev]    ),
    .datain_l  (1'b0             ),
    .outclock  (hbus_clk90       ),
    .oe        (1'b1             ),
    .outclocken(1'b1             ),
    .aset      (1'b0             ),
    .aclr      (1'b0             ),
    .sset      (1'b0             ),
    .sclr      (1'b0             ),
    .dataout   (hbus_clk_out[dev]),
    .oe_out    (                 )
  );
  defparam
    ddio_clk.width = 1,
    ddio_clk.power_up_high = "OFF",
    ddio_clk.intended_device_family = "Cyclone IV E",
    ddio_clk.oe_reg = "UNREGISTERED",
    ddio_clk.extend_oe_disable = "OFF",
    ddio_clk.invert_output = "OFF";
`endif
end
endgenerate

endmodule
