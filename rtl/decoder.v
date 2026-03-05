// ============================================================================
// decoder.sv — RV32I Instruction Decoder (Verilog-2001)
// ============================================================================
`include "brv32_defines.vh"

module decoder (
  input  [31:0] instr,
  output [4:0]  rs1_addr,
  output [4:0]  rs2_addr,
  output [4:0]  rd_addr,
  output [31:0] imm,
  output reg [3:0]  alu_op,
  output reg        alu_src,
  output reg        reg_wr_en,
  output reg        mem_rd_en,
  output reg        mem_wr_en,
  output reg [1:0]  mem_width,
  output reg        mem_sign_ext,
  output reg        branch,
  output reg        jal,
  output reg        jalr,
  output [2:0]  funct3,
  output reg        lui,
  output reg        auipc,
  output reg        ecall,
  output reg        ebreak,
  output reg        csr_en,
  output [11:0] csr_addr,
  output reg        illegal_instr
);
  wire [6:0] opcode = instr[6:0];
  wire [6:0] funct7 = instr[31:25];

  assign funct3   = instr[14:12];
  assign rs1_addr = instr[19:15];
  assign rs2_addr = instr[24:20];
  assign rd_addr  = instr[11:7];
  assign csr_addr = instr[31:20];

  // Immediate formats — all continuous assigns (no always block)
  wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
  wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
  wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
  wire [31:0] imm_u = {instr[31:12], 12'b0};
  wire [31:0] imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

  assign imm = (opcode == `OP_LOAD  || opcode == `OP_JALR || opcode == `OP_IMM)  ? imm_i :
               (opcode == `OP_STORE)                                               ? imm_s :
               (opcode == `OP_BRANCH)                                              ? imm_b :
               (opcode == `OP_LUI   || opcode == `OP_AUIPC)                       ? imm_u :
               (opcode == `OP_JAL)                                                 ? imm_j :
                                                                                     32'b0;

  always @(*) begin
    alu_op        = `ALU_ADD;
    alu_src       = 1'b0;
    reg_wr_en     = 1'b0;
    mem_rd_en     = 1'b0;
    mem_wr_en     = 1'b0;
    mem_width     = `MEM_WORD;
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
      `OP_LUI:    begin lui = 1'b1; reg_wr_en = 1'b1; end
      `OP_AUIPC:  begin auipc = 1'b1; reg_wr_en = 1'b1; end
      `OP_JAL:    begin jal = 1'b1; reg_wr_en = 1'b1; end
      `OP_JALR:   begin jalr = 1'b1; reg_wr_en = 1'b1; alu_src = 1'b1; end

      `OP_BRANCH: begin
        branch = 1'b1;
        case (funct3)
          3'b000, 3'b001: alu_op = `ALU_SUB;
          3'b100, 3'b101: alu_op = `ALU_SLT;
          3'b110, 3'b111: alu_op = `ALU_SLTU;
          default:        illegal_instr = 1'b1;
        endcase
      end

      `OP_LOAD: begin
        mem_rd_en    = 1'b1;
        reg_wr_en    = 1'b1;
        alu_src      = 1'b1;
        mem_width    = funct3[1:0];
        mem_sign_ext = ~funct3[2];
      end

      `OP_STORE: begin
        mem_wr_en = 1'b1;
        alu_src   = 1'b1;
        mem_width = funct3[1:0];
      end

      `OP_IMM: begin
        reg_wr_en = 1'b1;
        alu_src   = 1'b1;
        case (funct3)
          3'b000: alu_op = `ALU_ADD;
          3'b001: alu_op = `ALU_SLL;
          3'b010: alu_op = `ALU_SLT;
          3'b011: alu_op = `ALU_SLTU;
          3'b100: alu_op = `ALU_XOR;
          3'b101: alu_op = funct7[5] ? `ALU_SRA : `ALU_SRL;
          3'b110: alu_op = `ALU_OR;
          3'b111: alu_op = `ALU_AND;
        endcase
      end

      `OP_REG: begin
        reg_wr_en = 1'b1;
        case (funct3)
          3'b000: alu_op = funct7[5] ? `ALU_SUB : `ALU_ADD;
          3'b001: alu_op = `ALU_SLL;
          3'b010: alu_op = `ALU_SLT;
          3'b011: alu_op = `ALU_SLTU;
          3'b100: alu_op = `ALU_XOR;
          3'b101: alu_op = funct7[5] ? `ALU_SRA : `ALU_SRL;
          3'b110: alu_op = `ALU_OR;
          3'b111: alu_op = `ALU_AND;
        endcase
      end

      `OP_SYSTEM: begin
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

      `OP_FENCE: ; // NOP

      default: illegal_instr = 1'b1;
    endcase
  end
endmodule
