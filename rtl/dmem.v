// ============================================================================
// dmem.sv — Data Memory SRAM (Verilog-2001)
// Byte-addressable, supports LB/LH/LW/LBU/LHU/SB/SH/SW.
// All reads are combinational assigns to avoid iverilog always-block issues.
// ============================================================================
`include "brv32_defines.vh"

module dmem #(
  parameter DEPTH = 1024
)(
  input         clk,
  input         rst_n,
  input  [31:0] addr,
  input         rd_en,
  input         wr_en,
  input  [1:0]  width,
  input         sign_ext,
  input  [31:0] wdata,
  output [31:0] rdata
);
  reg [7:0] mem [0:(DEPTH*4)-1];
  integer i;

  // Pre-compute byte addresses
  wire [11:0] byte_addr = addr[11:0];
  wire [11:0] half_lo   = {addr[11:1], 1'b0};
  wire [11:0] half_hi   = {addr[11:1], 1'b1};
  wire [11:0] word_b0   = {addr[11:2], 2'b00};
  wire [11:0] word_b1   = {addr[11:2], 2'b01};
  wire [11:0] word_b2   = {addr[11:2], 2'b10};
  wire [11:0] word_b3   = {addr[11:2], 2'b11};

  // Read data wires
  wire [7:0]  rb    = mem[byte_addr];
  wire [7:0]  rh_lo = mem[half_lo];
  wire [7:0]  rh_hi = mem[half_hi];
  wire [7:0]  rw0   = mem[word_b0];
  wire [7:0]  rw1   = mem[word_b1];
  wire [7:0]  rw2   = mem[word_b2];
  wire [7:0]  rw3   = mem[word_b3];

  wire [31:0] rdata_byte = sign_ext ? {{24{rb[7]}},    rb}
                                    : {24'b0,           rb};
  wire [31:0] rdata_half = sign_ext ? {{16{rh_hi[7]}}, rh_hi, rh_lo}
                                    : {16'b0,           rh_hi, rh_lo};
  wire [31:0] rdata_word = {rw3, rw2, rw1, rw0};

  assign rdata = (!rd_en)             ? 32'b0       :
                 (width == `MEM_BYTE) ? rdata_byte  :
                 (width == `MEM_HALF) ? rdata_half  :
                                        rdata_word;

  // Write logic
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i = 0; i < DEPTH*4; i = i + 1)
        mem[i] <= 8'h00;
    end else if (wr_en) begin
      case (width)
        `MEM_BYTE: mem[byte_addr] <= wdata[7:0];
        `MEM_HALF: begin
          mem[half_lo] <= wdata[7:0];
          mem[half_hi] <= wdata[15:8];
        end
        default: begin  // MEM_WORD
          mem[word_b0] <= wdata[7:0];
          mem[word_b1] <= wdata[15:8];
          mem[word_b2] <= wdata[23:16];
          mem[word_b3] <= wdata[31:24];
        end
      endcase
    end
  end
endmodule
