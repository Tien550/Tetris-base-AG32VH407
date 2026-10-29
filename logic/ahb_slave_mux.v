module ahb_slave_mux #(parameter N = 2, ADDR_WIDTH = 32, DATA_WIDTH = 32) (
  input ahb_clock,
  input ahb_resetn,

  input      [1:0]            in_ahb_htrans,
  input                       in_ahb_hready,
  input      [ADDR_WIDTH-1:0] in_ahb_haddr,
  output reg                  in_ahb_hreadyout,
  output reg                  in_ahb_hresp,
  output reg [DATA_WIDTH-1:0] in_ahb_hrdata,

  output [N*2-1:0]          out_ahb_htrans,
  input  [N-1:0]            out_ahb_hreadyout,
  input  [N-1:0]            out_ahb_hresp,
  input  [N*DATA_WIDTH-1:0] out_ahb_hrdata
);
// The number of MSB used for mux selection.
parameter SELECT_BITS = $clog2(N);

wire [N-1:0] hsel_nxt;
reg  [N-1:0] hsel_reg;

genvar i;
generate
for (i = 0; i < N; i = i + 1) begin : gen_hsel
  assign hsel_nxt[i] = (in_ahb_haddr[ADDR_WIDTH-1-:SELECT_BITS] == i);
  always @(posedge ahb_clock or negedge ahb_resetn) begin
   if (!ahb_resetn)
     hsel_reg[i] <= 1'b0;
   else if (in_ahb_hready)
     hsel_reg[i] <= hsel_nxt[i];
  end

  assign out_ahb_htrans[i*2+:2] = hsel_nxt[i] ? in_ahb_htrans : 2'b00;
end
endgenerate

integer j;
always @ (*) begin
  in_ahb_hreadyout = 1'b1;
  in_ahb_hresp     = 1'b0;
  in_ahb_hrdata    = {DATA_WIDTH{1'b0}};
  for (j = 0; j < N; j = j + 1) begin
    if (hsel_reg[j]) begin
      in_ahb_hreadyout = in_ahb_hreadyout & out_ahb_hreadyout[j];
      in_ahb_hresp     = in_ahb_hresp     | out_ahb_hresp[j];
      in_ahb_hrdata    = in_ahb_hrdata    | out_ahb_hrdata[j*DATA_WIDTH+:DATA_WIDTH];
    end
  end
end

endmodule
