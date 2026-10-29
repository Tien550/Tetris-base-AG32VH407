module ahb2fifo(
  input         reset,
  input         ahb_clock,
  input  [1:0]  ahb_htrans,
  input         ahb_hready,
  input         ahb_hwrite,
  input  [31:0] ahb_haddr,     // 1 extra bit to access registers
  input  [2:0]  ahb_hsize,
  input  [2:0]  ahb_hburst,
  input  [31:0] ahb_hwdata,
  output [31:0] ahb_hrdata,
  output        ahb_hresp,
  output        ahb_hreadyout,

  output [1:0]  mst_ahb_htrans,
  output        mst_ahb_hready,
  output        mst_ahb_hwrite,
  output [31:0] mst_ahb_haddr,
  output [2:0]  mst_ahb_hsize,
  output [2:0]  mst_ahb_hburst,
  output [31:0] mst_ahb_hwdata,
  input  [31:0] mst_ahb_hrdata,
  input         mst_ahb_hresp,
  input         mst_ahb_hreadyout,

  input             out_fifo_half_full,
  output reg        out_fifo_wrreq,
  output     [31:0] out_fifo_data,

  input      [7:0]  in_fifo_rdusedw,
  output reg        in_fifo_rdreq,
  input      [31:0] in_fifo_q,

  input      dma_running,
  output reg dma_ready
);

wire ahb_fifo_select;
reg  ahb_fifo_active;

always @ (posedge ahb_clock or posedge reset) begin
  if (reset) begin
    out_fifo_wrreq <= 1'b0;
  end else if (ahb_fifo_select && ahb_hreadyout && ahb_htrans[1] && ahb_hwrite) begin
    out_fifo_wrreq <= 1'b1;
  end else begin
    out_fifo_wrreq <= 1'b0;
  end
end

always @ (posedge ahb_clock or posedge reset) begin
  if (reset) begin
    in_fifo_rdreq <= 1'b0;
  end else if (ahb_fifo_select && ahb_hreadyout && ahb_htrans[1] && !ahb_hwrite) begin
    in_fifo_rdreq <= 1'b1;
  end else begin
    in_fifo_rdreq <= 1'b0;
  end
end

always @ (posedge ahb_clock or posedge reset) begin
  if (reset) begin
    ahb_fifo_active <= 1'b0;
  end else if (ahb_hready) begin
    ahb_fifo_active <= ahb_fifo_select;
  end
end

assign ahb_hreadyout = ahb_fifo_active ? 1'b1  : mst_ahb_hreadyout;
assign ahb_hrdata    = ahb_fifo_active ? in_fifo_q : mst_ahb_hrdata;
assign ahb_hresp     = ahb_fifo_active ? 1'b0  : mst_ahb_hresp;

// Select fifo when ahb_haddr MSB is 7 (system AHB address 32'h7xxx_xxxx). Otherwise select the master AHB.
assign ahb_fifo_select = ahb_haddr[31:28] == 4'h7;
assign mst_ahb_htrans = ahb_fifo_select ? 2'b0 : ahb_htrans;
assign mst_ahb_hready = ahb_hready;
assign mst_ahb_hwrite = ahb_hwrite;
assign mst_ahb_haddr  = ahb_haddr;
assign mst_ahb_hsize  = ahb_hsize;
assign mst_ahb_hburst = ahb_hburst;
assign mst_ahb_hwdata = ahb_hwdata;

always @ (posedge ahb_clock or posedge reset) begin
  if (reset) begin
    dma_ready <= 1'b0;
  end else if (!dma_running) begin
    dma_ready <= 1'b0;
  end else if (ahb_fifo_select) begin
    if (ahb_hwrite) begin
      // De-assert the ready signal when FIFO is half full.
      dma_ready <= !out_fifo_half_full;
    end else begin
      // To make sure an HBUS operation (4 bursts) is done without interruption, for burst1/4/8/16, assert the ready 
      // signal when FIFO has at least 4/16/32/64 words.
      dma_ready <= in_fifo_rdusedw >= (mst_ahb_hburst[2:1] == 0 ? 4 : mst_ahb_hburst[2:1] == 1 ? 16 : mst_ahb_hburst[2:1] == 2 ? 32 : 64);
    end
  end else begin
    dma_ready <= 1'b1;
  end
end

assign out_fifo_data = ahb_hwdata;

endmodule
