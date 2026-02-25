// ============================================================================
// dmem.sv — Data Memory (SRAM, 4 KB default)
// ============================================================================
// Byte-addressable with sub-word read/write support (LB/LH/LBU/LHU/SB/SH).
// ============================================================================
import riscv_pkg::*;

module dmem #(
  parameter DEPTH = 1024   // Number of 32-bit words
)(
  input  logic        clk,
  input  logic        rst_n,

  input  logic [31:0] addr,
  input  logic        rd_en,
  input  logic        wr_en,
  input  mem_width_e  width,
  input  logic        sign_ext,
  input  logic [31:0] wdata,
  output logic [31:0] rdata
);

  logic [7:0] mem [0:(DEPTH*4)-1];
  logic [1:0] byte_offset;
  logic [31:0] word_raw;

  assign byte_offset = addr[1:0];

  // ── Read logic ─────────────────────────────────────────────────────
  always_comb begin
    // Read aligned 32-bit word
    word_raw = {mem[{addr[31:2], 2'b11}],
                mem[{addr[31:2], 2'b10}],
                mem[{addr[31:2], 2'b01}],
                mem[{addr[31:2], 2'b00}]};

    rdata = 32'b0;
    if (rd_en) begin
      case (width)
        MEM_BYTE: begin
          logic [7:0] b;
          b = mem[addr[$clog2(DEPTH*4)-1:0]];
          rdata = sign_ext ? {{24{b[7]}}, b} : {24'b0, b};
        end
        MEM_HALF: begin
          logic [15:0] h;
          h = {mem[{addr[$clog2(DEPTH*4)-1:1], 1'b1}],
               mem[{addr[$clog2(DEPTH*4)-1:1], 1'b0}]};
          rdata = sign_ext ? {{16{h[15]}}, h} : {16'b0, h};
        end
        MEM_WORD: begin
          rdata = word_raw;
        end
        default: rdata = 32'b0;
      endcase
    end
  end

  // ── Write logic ────────────────────────────────────────────────────
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < DEPTH*4; i++)
        mem[i] = 8'h00;
    end else if (wr_en) begin
      case (width)
        MEM_BYTE: begin
          mem[addr[$clog2(DEPTH*4)-1:0]] <= wdata[7:0];
        end
        MEM_HALF: begin
          mem[{addr[$clog2(DEPTH*4)-1:1], 1'b1}] <= wdata[15:8];
          mem[{addr[$clog2(DEPTH*4)-1:1], 1'b0}] <= wdata[7:0];
        end
        MEM_WORD: begin
          mem[{addr[$clog2(DEPTH*4)-1:2], 2'b00}] <= wdata[7:0];
          mem[{addr[$clog2(DEPTH*4)-1:2], 2'b01}] <= wdata[15:8];
          mem[{addr[$clog2(DEPTH*4)-1:2], 2'b10}] <= wdata[23:16];
          mem[{addr[$clog2(DEPTH*4)-1:2], 2'b11}] <= wdata[31:24];
        end
        default: ;
      endcase
    end
  end

endmodule
