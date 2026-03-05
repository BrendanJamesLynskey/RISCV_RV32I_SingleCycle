// ============================================================================
// brv32_core.sv — BRV32 RISC-V CPU Core RV32I single-cycle (Verilog-2001)
// ============================================================================
`include "brv32_defines.vh"

module brv32_core (
  input         clk,
  input         rst_n,
  output [31:0] imem_addr,
  input  [31:0] imem_rdata,
  output [31:0] dmem_addr,
  output        dmem_rd_en,
  output        dmem_wr_en,
  output [1:0]  dmem_width,
  output        dmem_sign_ext,
  output [31:0] dmem_wdata,
  input  [31:0] dmem_rdata,
  input         ext_irq,
  input         timer_irq
);
  // ── Program Counter ──────────────────────────────────────────────────────
  reg [31:0] pc;
  reg [31:0] pc_next;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) pc <= 32'h0;
    else        pc <= pc_next;
  end
  assign imem_addr = pc;

  // ── Decode wires ─────────────────────────────────────────────────────────
  wire [31:0] instr = imem_rdata;
  wire [4:0]  rs1_addr, rs2_addr, rd_addr;
  wire [31:0] imm;
  wire [3:0]  alu_op;
  wire        alu_src, reg_wr_en, mem_rd_en_dec, mem_wr_en_dec;
  wire [1:0]  mem_width_dec;
  wire        mem_sign_ext_dec;
  wire        branch_dec, jal_dec, jalr_dec, lui_dec, auipc_dec;
  wire        ecall_dec, ebreak_dec, csr_en_dec, illegal_instr;
  wire [2:0]  funct3;
  wire [11:0] csr_addr_dec;

  decoder u_decoder (
    .instr        (instr),
    .rs1_addr     (rs1_addr),    .rs2_addr     (rs2_addr),
    .rd_addr      (rd_addr),     .imm          (imm),
    .alu_op       (alu_op),      .alu_src      (alu_src),
    .reg_wr_en    (reg_wr_en),   .mem_rd_en    (mem_rd_en_dec),
    .mem_wr_en    (mem_wr_en_dec),.mem_width   (mem_width_dec),
    .mem_sign_ext (mem_sign_ext_dec),
    .branch       (branch_dec),  .jal          (jal_dec),
    .jalr         (jalr_dec),    .funct3       (funct3),
    .lui          (lui_dec),     .auipc        (auipc_dec),
    .ecall        (ecall_dec),   .ebreak       (ebreak_dec),
    .csr_en       (csr_en_dec),  .csr_addr     (csr_addr_dec),
    .illegal_instr(illegal_instr)
  );

  // ── Register File ────────────────────────────────────────────────────────
  wire [31:0] rs1_data, rs2_data;
  reg  [31:0] rd_data;
  wire        rd_wr_en;

  regfile u_regfile (
    .clk(clk), .rst_n(rst_n),
    .rs1_addr(rs1_addr), .rs1_data(rs1_data),
    .rs2_addr(rs2_addr), .rs2_data(rs2_data),
    .wr_en(rd_wr_en),    .rd_addr(rd_addr),
    .rd_data(rd_data)
  );

  // ── ALU ──────────────────────────────────────────────────────────────────
  wire [31:0] alu_b   = alu_src ? imm : rs2_data;
  wire [31:0] alu_result;
  wire        alu_zero;

  alu u_alu (
    .a(rs1_data), .b(alu_b),
    .op(alu_op),
    .result(alu_result), .zero(alu_zero)
  );

  // ── CSR ──────────────────────────────────────────────────────────────────
  wire [31:0] csr_rdata, mtvec_out, mepc_out;
  wire        irq_pending;
  reg         trap_enter;
  reg  [31:0] trap_cause, trap_val;
  wire        mret_sig = (instr == 32'h3020_0073);
  wire [31:0] csr_wdata = funct3[2] ? {27'b0, rs1_addr} : rs1_data;

  csr u_csr (
    .clk(clk),          .rst_n(rst_n),
    .csr_en(csr_en_dec & ~trap_enter),
    .csr_addr(csr_addr_dec), .csr_op(funct3),
    .csr_wdata(csr_wdata),   .csr_rdata(csr_rdata),
    .trap_enter(trap_enter), .trap_cause(trap_cause),
    .trap_val(trap_val),     .trap_pc(pc),
    .mtvec_out(mtvec_out),   .mepc_out(mepc_out),
    .mret(mret_sig),
    .ext_irq(ext_irq),       .timer_irq(timer_irq),
    .instr_retired(1'b1),    .irq_pending(irq_pending)
  );

  // ── Branch Logic ─────────────────────────────────────────────────────────
  reg branch_taken;
  always @(*) begin
    branch_taken = 1'b0;
    if (branch_dec) begin
      case (funct3)
        3'b000: branch_taken = alu_zero;
        3'b001: branch_taken = ~alu_zero;
        3'b100: branch_taken = alu_result[0];
        3'b101: branch_taken = ~alu_result[0];
        3'b110: branch_taken = alu_result[0];
        3'b111: branch_taken = ~alu_result[0];
        default: branch_taken = 1'b0;
      endcase
    end
  end

  // ── Trap Logic ───────────────────────────────────────────────────────────
  always @(*) begin
    trap_enter = 1'b0; trap_cause = 32'b0; trap_val = 32'b0;
    if (illegal_instr) begin
      trap_enter = 1'b1; trap_cause = 32'd2; trap_val = instr;
    end else if (ecall_dec) begin
      trap_enter = 1'b1; trap_cause = 32'd11;
    end else if (ebreak_dec) begin
      trap_enter = 1'b1; trap_cause = 32'd3;
    end else if (irq_pending) begin
      trap_enter = 1'b1; trap_cause = {1'b1, 31'd11};
    end
  end

  // ── Data Memory Interface ────────────────────────────────────────────────
  assign dmem_addr     = alu_result;
  assign dmem_rd_en    = mem_rd_en_dec & ~trap_enter;
  assign dmem_wr_en    = mem_wr_en_dec & ~trap_enter;
  assign dmem_width    = mem_width_dec;
  assign dmem_sign_ext = mem_sign_ext_dec;
  assign dmem_wdata    = rs2_data;

  // ── Writeback MUX ────────────────────────────────────────────────────────
  always @(*) begin
    if      (lui_dec)                 rd_data = imm;
    else if (auipc_dec)               rd_data = pc + imm;
    else if (jal_dec || jalr_dec)     rd_data = pc + 32'd4;
    else if (mem_rd_en_dec)           rd_data = dmem_rdata;
    else if (csr_en_dec)              rd_data = csr_rdata;
    else                              rd_data = alu_result;
  end
  assign rd_wr_en = reg_wr_en & ~trap_enter;

  // ── Next PC ──────────────────────────────────────────────────────────────
  always @(*) begin
    if      (trap_enter)   pc_next = mtvec_out;
    else if (mret_sig)     pc_next = mepc_out;
    else if (jal_dec)      pc_next = pc + imm;
    else if (jalr_dec)     pc_next = alu_result & 32'hFFFF_FFFE;
    else if (branch_taken) pc_next = pc + imm;
    else                   pc_next = pc + 32'd4;
  end
endmodule
