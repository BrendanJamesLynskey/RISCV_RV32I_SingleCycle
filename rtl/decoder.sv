// ============================================================================
// decoder.sv — RV32I Instruction Decoder
// ============================================================================
// Decodes a 32-bit instruction into control signals, immediate value,
// register addresses, and ALU operation.
// ============================================================================
import riscv_pkg::*;

module decoder (
  input  logic [31:0] instr,

  // Register addresses
  output logic [4:0]  rs1_addr,
  output logic [4:0]  rs2_addr,
  output logic [4:0]  rd_addr,

  // Immediate
  output logic [31:0] imm,

  // ALU
  output alu_op_e     alu_op,
  output logic        alu_src,      // 0 = rs2, 1 = immediate

  // Control
  output logic        reg_wr_en,
  output logic        mem_rd_en,
  output logic        mem_wr_en,
  output mem_width_e  mem_width,
  output logic        mem_sign_ext,
  output logic        branch,
  output logic        jal,
  output logic        jalr,
  output logic [2:0]  funct3,
  output logic        lui,
  output logic        auipc,
  output logic        ecall,
  output logic        ebreak,
  output logic        csr_en,
  output logic [11:0] csr_addr,
  output logic        illegal_instr
);

  opcode_e opcode;
  logic [6:0] funct7;

  assign opcode   = opcode_e'(instr[6:0]);
  assign funct3   = instr[14:12];
  assign funct7   = instr[31:25];
  assign rs1_addr = instr[19:15];
  assign rs2_addr = instr[24:20];
  assign rd_addr  = instr[11:7];
  assign csr_addr = instr[31:20];

  // ── Immediate Generation ─────────────────────────────────────────────
  always_comb begin
    case (opcode)
      OP_LOAD, OP_JALR, OP_IMM:                                          // I-type
        imm = {{20{instr[31]}}, instr[31:20]};
      OP_STORE:                                                            // S-type
        imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
      OP_BRANCH:                                                           // B-type
        imm = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
      OP_LUI, OP_AUIPC:                                                   // U-type
        imm = {instr[31:12], 12'b0};
      OP_JAL:                                                              // J-type
        imm = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
      default:
        imm = 32'b0;
    endcase
  end

  // ── Control Signal Generation ────────────────────────────────────────
  always_comb begin
    // Defaults
    alu_op        = ALU_ADD;
    alu_src       = 1'b0;
    reg_wr_en     = 1'b0;
    mem_rd_en     = 1'b0;
    mem_wr_en     = 1'b0;
    mem_width     = MEM_WORD;
    mem_sign_ext  = 1'b1;
    branch        = 1'b0;
    jal           = 1'b0;
    jalr          = 1'b0;
    lui           = 1'b0;
    auipc         = 1'b0;
    ecall         = 1'b0;
    ebreak        = 1'b0;
    csr_en        = 1'b0;
    illegal_instr = 1'b0;

    case (opcode)
      OP_LUI: begin
        lui       = 1'b1;
        reg_wr_en = 1'b1;
      end

      OP_AUIPC: begin
        auipc     = 1'b1;
        reg_wr_en = 1'b1;
      end

      OP_JAL: begin
        jal       = 1'b1;
        reg_wr_en = 1'b1;
      end

      OP_JALR: begin
        jalr      = 1'b1;
        reg_wr_en = 1'b1;
        alu_src   = 1'b1;
      end

      OP_BRANCH: begin
        branch = 1'b1;
        case (funct3)
          3'b000:  alu_op = ALU_SUB;  // BEQ
          3'b001:  alu_op = ALU_SUB;  // BNE
          3'b100:  alu_op = ALU_SLT;  // BLT
          3'b101:  alu_op = ALU_SLT;  // BGE
          3'b110:  alu_op = ALU_SLTU; // BLTU
          3'b111:  alu_op = ALU_SLTU; // BGEU
          default: illegal_instr = 1'b1;
        endcase
      end

      OP_LOAD: begin
        mem_rd_en  = 1'b1;
        reg_wr_en  = 1'b1;
        alu_src    = 1'b1;
        mem_width  = mem_width_e'(funct3[1:0]);
        mem_sign_ext = ~funct3[2];
      end

      OP_STORE: begin
        mem_wr_en = 1'b1;
        alu_src   = 1'b1;
        mem_width = mem_width_e'(funct3[1:0]);
      end

      OP_IMM: begin
        reg_wr_en = 1'b1;
        alu_src   = 1'b1;
        case (funct3)
          3'b000: alu_op = ALU_ADD;                                        // ADDI
          3'b001: alu_op = ALU_SLL;                                        // SLLI
          3'b010: alu_op = ALU_SLT;                                        // SLTI
          3'b011: alu_op = ALU_SLTU;                                       // SLTIU
          3'b100: alu_op = ALU_XOR;                                        // XORI
          3'b101: alu_op = alu_op_e'(funct7[5] ? ALU_SRA : ALU_SRL);       // SRAI / SRLI
          3'b110: alu_op = ALU_OR;                                         // ORI
          3'b111: alu_op = ALU_AND;                                        // ANDI
        endcase
      end

      OP_REG: begin
        reg_wr_en = 1'b1;
        case (funct3)
          3'b000: alu_op = alu_op_e'(funct7[5] ? ALU_SUB : ALU_ADD);       // SUB / ADD
          3'b001: alu_op = ALU_SLL;
          3'b010: alu_op = ALU_SLT;
          3'b011: alu_op = ALU_SLTU;
          3'b100: alu_op = ALU_XOR;
          3'b101: alu_op = alu_op_e'(funct7[5] ? ALU_SRA : ALU_SRL);
          3'b110: alu_op = ALU_OR;
          3'b111: alu_op = ALU_AND;
        endcase
      end

      OP_SYSTEM: begin
        if (funct3 == 3'b000) begin
          case (instr[31:20])
            12'h000: ecall  = 1'b1;
            12'h001: ebreak = 1'b1;
            default: illegal_instr = 1'b1;
          endcase
        end else begin
          csr_en    = 1'b1;
          reg_wr_en = 1'b1;
        end
      end

      OP_FENCE: begin
        // NOP for single-hart, in-order core
      end

      default: begin
        illegal_instr = 1'b1;
      end
    endcase
  end

endmodule
