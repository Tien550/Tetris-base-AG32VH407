module ahb2reg(
  input              ahb_clock,
  input              ahb_resetn,
  input       [1:0]  ahb_htrans,
  input              ahb_hready,
  input              ahb_hwrite,
  input       [31:0] ahb_haddr,
  input       [2:0]  ahb_hsize,
  input       [2:0]  ahb_hburst,
  input       [31:0] ahb_hwdata,
  output reg         ahb_hreadyout,
  output             ahb_hresp,
  output reg  [31:0] ahb_hrdata
);
assign ahb_hresp = 1'b0;

reg [15:0] haddr_reg; // Only use the lower 16 bits.
reg hwrite_reg;
reg ahb_data_phase;

parameter ADDR_DATA0 = 16'h0;
parameter ADDR_DATA1 = 16'h4;

reg [31:0] data_reg0;
reg [31:0] data_reg1;

wire ahb_sel = ahb_htrans[1] && ahb_hreadyout;
wire ahb_write = ahb_data_phase && !ahb_hreadyout &&  hwrite_reg;
wire ahb_read  = ahb_data_phase && !ahb_hreadyout && !hwrite_reg;

always @(posedge ahb_clock or negedge ahb_resetn) begin
  if (!ahb_resetn) begin
    haddr_reg  <= 'h0;
    hwrite_reg <= 1'b0;
  end else if (ahb_sel) begin
    haddr_reg  <= ahb_haddr[15:0];
    hwrite_reg <= ahb_hwrite;
  end
end

always @(posedge ahb_clock or negedge ahb_resetn) begin
  if (!ahb_resetn) begin
    ahb_data_phase <= 1'b0;
  end else if (ahb_hreadyout) begin
    ahb_data_phase <= ahb_htrans[1];
  end
end

always @(posedge ahb_clock or negedge ahb_resetn) begin
  if (!ahb_resetn) begin
    ahb_hreadyout <= 1'b1;
  end else if (ahb_sel) begin
    ahb_hreadyout <= 1'b0;
  end else begin
    ahb_hreadyout <= 1'b1;
  end
end

always @ (posedge ahb_clock or negedge ahb_resetn) begin
  if (!ahb_resetn) begin
    data_reg0 <= 32'h0;
  end else if (ahb_write && haddr_reg == ADDR_DATA0) begin
    data_reg0 <= ahb_hwdata;
  end
end

always @ (posedge ahb_clock or negedge ahb_resetn) begin
  if (!ahb_resetn) begin
    data_reg1 <= 32'h0;
  end else if (ahb_write && haddr_reg == ADDR_DATA1) begin
    data_reg1 <= ahb_hwdata;
  end
end

always @ (posedge ahb_clock or negedge ahb_resetn) begin
  if (!ahb_resetn) begin
    ahb_hrdata <= 32'h0;
  end else if (ahb_read) begin
    case (haddr_reg)
      ADDR_DATA0: ahb_hrdata <= data_reg0;
      ADDR_DATA1: ahb_hrdata <= data_reg1;
    endcase
  end
end

endmodule
