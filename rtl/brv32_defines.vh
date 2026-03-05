// ============================================================================
// brv32_defines.vh — Shared defines for BRV32 MCU (Verilog-2001 compatible)
// ============================================================================
`ifndef BRV32_DEFINES_VH
`define BRV32_DEFINES_VH

// ── Instruction Opcodes ──────────────────────────────────────────────────────
`define OP_LUI      7'b0110111
`define OP_AUIPC    7'b0010111
`define OP_JAL      7'b1101111
`define OP_JALR     7'b1100111
`define OP_BRANCH   7'b1100011
`define OP_LOAD     7'b0000011
`define OP_STORE    7'b0100011
`define OP_IMM      7'b0010011
`define OP_REG      7'b0110011
`define OP_FENCE    7'b0001111
`define OP_SYSTEM   7'b1110011

// ── ALU Operations ───────────────────────────────────────────────────────────
`define ALU_ADD    4'b0000
`define ALU_SUB    4'b1000
`define ALU_SLL    4'b0001
`define ALU_SLT    4'b0010
`define ALU_SLTU   4'b0011
`define ALU_XOR    4'b0100
`define ALU_SRL    4'b0101
`define ALU_SRA    4'b1101
`define ALU_OR     4'b0110
`define ALU_AND    4'b0111

// ── Memory Access Width ──────────────────────────────────────────────────────
`define MEM_BYTE   2'b00
`define MEM_HALF   2'b01
`define MEM_WORD   2'b10

// ── CSR Addresses ────────────────────────────────────────────────────────────
`define CSR_MSTATUS   12'h300
`define CSR_MIE       12'h304
`define CSR_MTVEC     12'h305
`define CSR_MSCRATCH  12'h340
`define CSR_MEPC      12'h341
`define CSR_MCAUSE    12'h342
`define CSR_MTVAL     12'h343
`define CSR_MIP       12'h344
`define CSR_MCYCLE    12'hB00
`define CSR_MINSTRET  12'hB02
`define CSR_MVENDORID 12'hF11
`define CSR_MARCHID   12'hF12
`define CSR_MHARTID   12'hF14

`endif
