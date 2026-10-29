module hram_ip #(parameter RGB_BITS = 16) (
  inout       [7:0]          hbus_adq,
  output tri0                hbus_clk_out,
  output tri0                hbus_csn,
  output tri0                hbus_resetn,
  inout                      hbus_rwds,
  input                      hbus_clk90_out_data,
  input                      hbus_clk90_out_en,
  input                      hbus_clk_out_data,
  input                      hbus_clk_out_en,
  output                     rgb_hsync,
  output                     rgb_vsync,
  output                     rgb_de,
  output                     rgb_dclk,
  output      [RGB_BITS-1:0] rgb_data,
  input                      sys_clock,
  input                      bus_clock,
  input                      resetn,
  input                      stop,
  input       [1:0]          mem_ahb_htrans,
  input                      mem_ahb_hready,
  input                      mem_ahb_hwrite,
  input       [31:0]         mem_ahb_haddr,
  input       [2:0]          mem_ahb_hsize,
  input       [2:0]          mem_ahb_hburst,
  input       [31:0]         mem_ahb_hwdata,
  output tri1                mem_ahb_hreadyout,
  output tri0                mem_ahb_hresp,
  output tri0 [31:0]         mem_ahb_hrdata,
  output tri0                slave_ahb_hsel,
  output tri1                slave_ahb_hready,
  input                      slave_ahb_hreadyout,
  output tri0 [1:0]          slave_ahb_htrans,
  output tri0 [2:0]          slave_ahb_hsize,
  output tri0 [2:0]          slave_ahb_hburst,
  output tri0                slave_ahb_hwrite,
  output tri0 [31:0]         slave_ahb_haddr,
  output tri0 [31:0]         slave_ahb_hwdata,
  input                      slave_ahb_hresp,
  input       [31:0]         slave_ahb_hrdata,
  output tri0 [3:0]          ext_dma_DMACBREQ,
  output tri0 [3:0]          ext_dma_DMACLBREQ,
  output tri0 [3:0]          ext_dma_DMACSREQ,
  output tri0 [3:0]          ext_dma_DMACLSREQ,
  input       [3:0]          ext_dma_DMACCLR,
  input       [3:0]          ext_dma_DMACTC,
  output tri0 [3:0]          local_int
);
assign slave_ahb_hsel = slave_ahb_htrans[1];

wire hbus_clk   = hbus_clk_out_data;
wire hbus_clk90 = hbus_clk90_out_data;

wire        rgb_ahb_hready;
wire        rgb_ahb_hreadyout;
wire [1:0]  rgb_ahb_htrans;
wire [2:0]  rgb_ahb_hsize;
wire [2:0]  rgb_ahb_hburst;
wire        rgb_ahb_hwrite;
wire [31:0] rgb_ahb_haddr;
wire [31:0] rgb_ahb_hwdata;
wire        rgb_ahb_hresp;
wire [31:0] rgb_ahb_hrdata;

wire        hbus_ahb_hready = mem_ahb_hready;
wire [2:0]  hbus_ahb_hsize  = mem_ahb_hsize;
wire [2:0]  hbus_ahb_hburst = mem_ahb_hburst;
wire        hbus_ahb_hwrite = mem_ahb_hwrite;
wire [31:0] hbus_ahb_haddr  = mem_ahb_haddr;
wire [31:0] hbus_ahb_hwdata = mem_ahb_hwdata;
wire        hbus_ahb_hreadyout;
wire [1:0]  hbus_ahb_htrans;
wire        hbus_ahb_hresp;
wire [31:0] hbus_ahb_hrdata;

wire        reg_ahb_hready = mem_ahb_hready;
wire [2:0]  reg_ahb_hsize  = mem_ahb_hsize;
wire [2:0]  reg_ahb_hburst = mem_ahb_hburst;
wire        reg_ahb_hwrite = mem_ahb_hwrite;
wire [31:0] reg_ahb_haddr  = mem_ahb_haddr;
wire [31:0] reg_ahb_hwdata = mem_ahb_hwdata;
wire        reg_ahb_hreadyout;
wire [1:0]  reg_ahb_htrans;
wire        reg_ahb_hresp;
wire [31:0] reg_ahb_hrdata;

// Uses 1 more address bit than ahb2hbus for mux selection.
ahb_slave_mux #(.N(2), .ADDR_WIDTH(25), .DATA_WIDTH(32)) u_ahb_mux(
  .ahb_clock (sys_clock),
  .ahb_resetn(resetn   ),

  .in_ahb_htrans   (mem_ahb_htrans     ),
  .in_ahb_hready   (mem_ahb_hready     ),
  .in_ahb_haddr    (mem_ahb_haddr[24:0]),
  .in_ahb_hrdata   (mem_ahb_hrdata     ),
  .in_ahb_hresp    (mem_ahb_hresp      ),
  .in_ahb_hreadyout(mem_ahb_hreadyout  ),

  .out_ahb_htrans   ({reg_ahb_htrans,    hbus_ahb_htrans}   ),
  .out_ahb_hrdata   ({reg_ahb_hrdata,    hbus_ahb_hrdata}   ),
  .out_ahb_hresp    ({reg_ahb_hresp,     hbus_ahb_hresp}    ),
  .out_ahb_hreadyout({reg_ahb_hreadyout, hbus_ahb_hreadyout})
);

ahb2hbus #(
  .ADDR_BITS   (23), // HyperRAM address in bytes (8MB).
  .DATA_BITS   (32), // AHB data width. Can be 32 or 64.
  .NUM_DEV     (1),  // Number of HyperRAM devices.
  .ADQ_BITS    (8),  // ADQ bits in each device
  .LATENCY_CNT (7)   // Supported latencies: 5, 6, 7
) u_ahb2hbus (
  .reset     (!resetn     ),
  .ahb_clock (sys_clock   ),
  .ahb_resetn(ahb_resetn  ),
  .dma_int   (local_int[0]),
  .dma_running(dma_running),
  .dma_ready (dma_ready   ),

  .ahb_htrans   (hbus_ahb_htrans     ),
  .ahb_hready   (hbus_ahb_hready     ),
  .ahb_hwrite   (hbus_ahb_hwrite     ),
  .ahb_haddr    (hbus_ahb_haddr[23:0]), // 1 more address bit for HyperRAM registers
  .ahb_hsize    (hbus_ahb_hsize      ),
  .ahb_hburst   (hbus_ahb_hburst     ),
  .ahb_hstrb    (4'b1111             ),
  .ahb_hwdata   (hbus_ahb_hwdata     ),
  .ahb_hrdata   (hbus_ahb_hrdata     ),
  .ahb_hresp    (hbus_ahb_hresp      ),
  .ahb_hreadyout(hbus_ahb_hreadyout  ),

  .mst_ahb_htrans   (rgb_ahb_htrans   ),
  .mst_ahb_hready   (rgb_ahb_hready   ),
  .mst_ahb_hwrite   (rgb_ahb_hwrite   ),
  .mst_ahb_haddr    (rgb_ahb_haddr    ),
  .mst_ahb_hsize    (rgb_ahb_hsize    ),
  .mst_ahb_hburst   (rgb_ahb_hburst   ),
  .mst_ahb_hwdata   (rgb_ahb_hwdata   ),
  .mst_ahb_hrdata   (rgb_ahb_hrdata   ),
  .mst_ahb_hresp    (rgb_ahb_hresp    ),
  .mst_ahb_hreadyout(rgb_ahb_hreadyout),

  .hbus_clk    (hbus_clk    ),
  .hbus_clk90  (hbus_clk90  ),
  .hbus_adq    (hbus_adq    ),
  .hbus_rwds   (hbus_rwds   ),
  .hbus_clk_out(hbus_clk_out),
  .hbus_csn    (hbus_csn    ),
  .hbus_resetn (hbus_resetn )
);

// Example AHB device.
ahb2reg u_regs(
  .ahb_clock    (sys_clock        ),
  .ahb_resetn   (resetn           ),
  .ahb_htrans   (reg_ahb_htrans   ),
  .ahb_hready   (reg_ahb_hready   ),
  .ahb_hwrite   (reg_ahb_hwrite   ),
  .ahb_haddr    (reg_ahb_haddr    ),
  .ahb_hsize    (reg_ahb_hsize    ),
  .ahb_hburst   (reg_ahb_hburst   ),
  .ahb_hwdata   (reg_ahb_hwdata   ),
  .ahb_hreadyout(reg_ahb_hreadyout),
  .ahb_hresp    (reg_ahb_hresp    ),
  .ahb_hrdata   (reg_ahb_hrdata   )
);

wire [RGB_BITS-1:0] rgb_bits;
`ifdef RGB888
if (RGB_BITS == 16)
  assign rgb_data = { rgb_bits[23:19], rgb_bits[15:10], rgb_bits[7:3] }; // Use upper bits only.
else
  assign rgb_data = rgb_bits;
`else // RGB565
assign rgb_data = rgb_bits;
`endif

wire        rgb_fifo_half_full;
wire        rgb_fifo_wrreq;
wire [31:0] rgb_fifo_data;

ahb2fifo u_ahb2fifo(
  .reset        (!resetn          ),
  .ahb_clock    (sys_clock        ),
  .ahb_htrans   (rgb_ahb_htrans   ),
  .ahb_hready   (rgb_ahb_hready   ),
  .ahb_hwrite   (rgb_ahb_hwrite   ),
  .ahb_haddr    (rgb_ahb_haddr    ),
  .ahb_hsize    (rgb_ahb_hsize    ),
  .ahb_hburst   (rgb_ahb_hburst   ),
  .ahb_hwdata   (rgb_ahb_hwdata   ),
  .ahb_hrdata   (rgb_ahb_hrdata   ),
  .ahb_hresp    (rgb_ahb_hresp    ),
  .ahb_hreadyout(rgb_ahb_hreadyout),

  .mst_ahb_htrans   (slave_ahb_htrans   ),
  .mst_ahb_hready   (slave_ahb_hready   ),
  .mst_ahb_hwrite   (slave_ahb_hwrite   ),
  .mst_ahb_haddr    (slave_ahb_haddr    ),
  .mst_ahb_hsize    (slave_ahb_hsize    ),
  .mst_ahb_hburst   (slave_ahb_hburst   ),
  .mst_ahb_hwdata   (slave_ahb_hwdata   ),
  .mst_ahb_hrdata   (slave_ahb_hrdata   ),
  .mst_ahb_hresp    (slave_ahb_hresp    ),
  .mst_ahb_hreadyout(slave_ahb_hreadyout),

  .out_fifo_half_full(rgb_fifo_half_full),
  .out_fifo_wrreq    (rgb_fifo_wrreq    ),
  .out_fifo_data     (rgb_fifo_data     ),

  .in_fifo_rdusedw(8'h0 ),
  .in_fifo_rdreq  (     ),
  .in_fifo_q      (32'h0),

  .dma_running(dma_running),
  .dma_ready  (dma_ready  )
);

fifo2rgb #(
  .HLINES  (800),
  .VLINES  (480),
  .RGB_BITS(RGB_BITS),
  .DCLK_DIV(6),  // Clock divider. Must be even. Minimum supported: 4
  .VPW     (4),  // VSYNC pulse width   (datasheet panel: typ 4, max 8)
  .VBP     (4),  // VSYNC back porch    (Tvbp 8 gom ca xung dong bo; max 12)
  .VFP     (8),  // VSYNC front porch   (typ 8, max 12)
  .HPW     (4),  // HSYNC pulse width   (typ 4, max 8)
  .HBP     (4),  // HSYNC back porch    (Thbp 8 gom ca xung dong bo; max 48)
  .HFP     (8),  // HSYNC front porch   (typ 8, max 48)
  .VDPOL   (1),  // VSYNC polarity. 0: Positive, 1: Negative.
  .HDPOL   (1),  // HSYNC polarity. 0: Positive, 1: Negative.
  .DCLKPOL (0)   // DCLK  polarity. 0: Positive, 1: Negative. (Gia tri SDK; da hoan lai tu 1)
) u_rgb(
  .reset(!resetn),

  .data_fifo_wrclk    (sys_clock         ),
  .data_fifo_rdclk    (sys_clock         ),
  .data_fifo_wrreq    (rgb_fifo_wrreq    ),
  .data_fifo_data     (rgb_fifo_data     ),
  .data_fifo_half_full(rgb_fifo_half_full),

  .rgb_hsync(rgb_hsync),
  .rgb_vsync(rgb_vsync),
  .rgb_de   (rgb_de   ),
  .rgb_dclk (rgb_dclk ),
  .rgb_data (rgb_bits )
);

endmodule
