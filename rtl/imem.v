// ============================================================================
// imem.sv — Instruction Memory ROM (Verilog-2001)
// ============================================================================
module imem #(
  parameter DEPTH     = 256,
  parameter INIT_FILE = "firmware.hex"
)(
  input  [31:0] addr,
  output [31:0] rdata
);
  reg [31:0] mem [0:DEPTH-1];
  integer i;

  initial begin
    for (i = 0; i < DEPTH; i = i + 1)
      mem[i] = 32'h0000_0013; // NOP
    if (INIT_FILE != "")
      $readmemh(INIT_FILE, mem);
  end

  assign rdata = mem[addr[31:2]];
endmodule
