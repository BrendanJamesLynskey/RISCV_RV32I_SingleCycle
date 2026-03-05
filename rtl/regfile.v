// ============================================================================
// regfile.v — 32x32 Register File (Verilog-2001)
// x0 hardwired to zero.
// NOTE: No write-first forwarding — reads return the registered value.
// In a single-cycle CPU the writeback happens before the next instruction's
// decode, so forwarding is not needed and causes combinational loops via
// the load-use path through dmem_rdata.
// ============================================================================
module regfile (
  input         clk,
  input         rst_n,
  input  [4:0]  rs1_addr,
  output [31:0] rs1_data,
  input  [4:0]  rs2_addr,
  output [31:0] rs2_data,
  input         wr_en,
  input  [4:0]  rd_addr,
  input  [31:0] rd_data
);
  reg [31:0] regs [1:31];
  integer i;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i = 1; i < 32; i = i + 1)
        regs[i] <= 32'b0;
    end else if (wr_en && rd_addr != 5'b0) begin
      regs[rd_addr] <= rd_data;
    end
  end

  // Pure registered reads — no combinational forwarding
  assign rs1_data = (rs1_addr == 5'b0) ? 32'b0 : regs[rs1_addr];
  assign rs2_data = (rs2_addr == 5'b0) ? 32'b0 : regs[rs2_addr];
endmodule
