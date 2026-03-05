// ============================================================================
// alu.sv — 32-bit ALU for BRV32 (Verilog-2001)
// ============================================================================
`include "brv32_defines.vh"

module alu (
  input  [31:0] a,
  input  [31:0] b,
  input  [3:0]  op,
  output reg [31:0] result,
  output        zero
);
  wire [4:0] shamt = b[4:0];

  always @(*) begin
    case (op)
      `ALU_ADD:  result = a + b;
      `ALU_SUB:  result = a - b;
      `ALU_SLL:  result = a << shamt;
      `ALU_SLT:  result = {31'b0, $signed(a) < $signed(b)};
      `ALU_SLTU: result = {31'b0, a < b};
      `ALU_XOR:  result = a ^ b;
      `ALU_SRL:  result = a >> shamt;
      `ALU_SRA:  result = $unsigned($signed(a) >>> shamt);
      `ALU_OR:   result = a | b;
      `ALU_AND:  result = a & b;
      default:   result = 32'b0;
    endcase
  end

  assign zero = (result == 32'b0);
endmodule
