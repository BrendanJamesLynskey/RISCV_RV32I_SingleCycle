# BRV32 RISC-V Microcontroller — Design Report

**RV32I Single-Cycle Core with Peripherals**
*Version 1.0 — February 2026*

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Architecture Overview](#2-architecture-overview)
3. [CPU Core (brv32_core)](#3-cpu-core-brv32_core)
4. [Memory System](#4-memory-system)
5. [Peripheral Subsystem](#5-peripheral-subsystem)
6. [Interrupt Architecture](#6-interrupt-architecture)
7. [Module Hierarchy and RTL File Map](#7-module-hierarchy-and-rtl-file-map)
8. [Verification Strategy](#8-verification-strategy)
9. [Synthesis Considerations](#9-synthesis-considerations)
10. [Future Enhancements](#10-future-enhancements)

---

## 1. Introduction

The BRV32 is a minimal yet complete RISC-V microcontroller designed for educational use and lightweight embedded applications. It implements the RV32I base integer instruction set (all 37 instructions) in a single-cycle architecture with machine-mode trap support and three memory-mapped peripherals: GPIO, UART, and Timer.

The design emphasises clarity, correctness, and testability over raw performance. Every module has clean interfaces, and the entire SoC is verified through both a SystemVerilog testbench and a CocoTB test suite with 15+ individual test cases.

| Parameter          | Value                                         |
|--------------------|-----------------------------------------------|
| **Target ISA**     | RISC-V RV32I (Base Integer, Machine-mode only) |
| **Microarchitecture** | Single-cycle (CPI = 1)                     |
| **Peripherals**    | 32-bit GPIO, UART (8N1), 32-bit Timer/Counter |
| **Language**       | SystemVerilog (IEEE 1800-2017)                |
| **Verification**   | SystemVerilog + CocoTB (Python)               |

---

## 2. Architecture Overview

The BRV32 MCU follows a Harvard architecture with separate instruction and data memory buses. The CPU core fetches one instruction per cycle from ROM, decodes it combinationally, executes it through the ALU, and writes back the result — all within a single clock cycle.

### 2.1 Memory Map

| Base Address    | Size   | Peripheral               |
|-----------------|--------|--------------------------|
| `0x0000_0000`   | 4 KB   | Instruction Memory (ROM) |
| `0x1000_0000`   | 4 KB   | Data Memory (SRAM)       |
| `0x2000_0000`   | 256 B  | GPIO                     |
| `0x2000_0100`   | 256 B  | UART                     |
| `0x2000_0200`   | 256 B  | Timer                    |

### 2.2 Bus Architecture

The data bus uses a simple combinational address decoder. The upper nibble of the 32-bit address selects between data memory (`0x1xxx_xxxx`) and the peripheral region (`0x2xxx_xxxx`). Within the peripheral region, bits [15:8] further select among GPIO, UART, and Timer. Read data is multiplexed back to the CPU via a priority MUX.

### 2.3 Block Diagram

```
                    ┌─────────────────────────────────────────────┐
                    │              brv32_mcu (SoC)                │
                    │                                             │
                    │  ┌───────────┐     ┌──────────────────┐    │
                    │  │           │────▶│  Instruction Mem  │    │
                    │  │           │◀────│     (imem)        │    │
                    │  │           │     └──────────────────┘    │
                    │  │ brv32_core│                              │
                    │  │           │     ┌──────────────────┐    │
                    │  │  ┌─────┐  │────▶│   Data Memory    │    │
                    │  │  │Decode│ │◀────│     (dmem)       │    │
                    │  │  ├─────┤  │     └──────────────────┘    │
                    │  │  │ ALU  │ │                              │
                    │  │  ├─────┤  │     ┌──────────────────┐    │
                    │  │  │RegF. │ │────▶│  GPIO  │ UART │Timer│ │
                    │  │  ├─────┤  │◀────│       Peripherals     │
                    │  │  │ CSR  │ │     └──────────────────┘    │
                    │  │  └─────┘  │                              │
                    │  └───────────┘                              │
                    └─────────────────────────────────────────────┘
```

---

## 3. CPU Core (brv32_core)

### 3.1 Datapath

The datapath consists of five functional units wired together combinationally: the program counter (PC) register, the instruction decoder, the 32×32 register file, the ALU, and the CSR unit. On each rising clock edge, the PC advances to the next instruction address, which is computed from the current instruction's type (sequential, branch, jump, or trap vector).

### 3.2 Instruction Decoder

The decoder (`decoder.sv`) extracts all control signals from the 32-bit instruction word in a single combinational block. It handles all six RISC-V instruction formats:

- **R-type** — register-register ALU operations (ADD, SUB, SLT, etc.)
- **I-type** — immediate ALU and loads (ADDI, LW, JALR, etc.)
- **S-type** — stores (SW, SH, SB)
- **B-type** — branches (BEQ, BNE, BLT, BGE, BLTU, BGEU)
- **U-type** — upper-immediate (LUI, AUIPC)
- **J-type** — unconditional jump (JAL)

The decoder also identifies system instructions (ECALL, EBREAK, CSR operations) and raises an `illegal_instr` flag for unrecognised opcodes.

### 3.3 Register File

The register file (`regfile.sv`) provides 31 general-purpose 32-bit registers (x1–x31) with x0 hardwired to zero. It has two combinational read ports and one synchronous write port. Write-first forwarding ensures that a read-after-write to the same register within the same cycle returns the new value.

### 3.4 ALU

The ALU (`alu.sv`) supports all ten RV32I operations:

| Operation | Encoding | Description                     |
|-----------|----------|---------------------------------|
| ADD       | `0000`   | Addition                        |
| SUB       | `1000`   | Subtraction                     |
| SLL       | `0001`   | Shift left logical              |
| SLT       | `0010`   | Set less than (signed)          |
| SLTU      | `0011`   | Set less than (unsigned)        |
| XOR       | `0100`   | Bitwise exclusive OR            |
| SRL       | `0101`   | Shift right logical             |
| SRA       | `1101`   | Shift right arithmetic          |
| OR        | `0110`   | Bitwise OR                      |
| AND       | `0111`   | Bitwise AND                     |

All operations are purely combinational. A `zero` flag output is used by the branch logic.

### 3.5 Branch and Jump Logic

Branch resolution uses the ALU result: for BEQ/BNE the zero flag is checked directly; for BLT/BGE/BLTU/BGEU the SLT/SLTU result's LSB is examined.

The next-PC MUX prioritises (highest to lowest): trap entry → MRET → JAL → JALR → taken branch → sequential (PC + 4).

### 3.6 CSR Unit

The CSR unit (`csr.sv`) implements the minimum M-mode register set:

| CSR Address | Name       | Description                         |
|-------------|------------|-------------------------------------|
| `0x300`     | mstatus    | Machine status (MIE, MPIE)          |
| `0x304`     | mie        | Machine interrupt enable            |
| `0x305`     | mtvec      | Machine trap-handler base address   |
| `0x340`     | mscratch   | Scratch register for trap handlers  |
| `0x341`     | mepc       | Machine exception program counter   |
| `0x342`     | mcause     | Machine trap cause                  |
| `0x343`     | mtval      | Machine trap value                  |
| `0x344`     | mip        | Machine interrupt pending           |
| `0xB00`     | mcycle     | Cycle counter (low 32 bits)         |
| `0xB02`     | minstret   | Instructions retired (low 32 bits)  |
| `0xF11`     | mvendorid  | Vendor ID (reads 0)                 |
| `0xF12`     | marchid    | Architecture ID (reads 0)           |
| `0xF14`     | mhartid    | Hart ID (reads 0)                   |

The unit supports CSRRW, CSRRS, CSRRC operations and their immediate variants. On trap entry, MIE is saved to MPIE and cleared; on MRET, the reverse occurs.

---

## 4. Memory System

### 4.1 Instruction Memory (imem.sv)

The instruction memory is a single-port synchronous ROM initialised from a hex file via `$readmemh`. It holds 1024 words (4 KB) by default and presents the instruction at the addressed word on every cycle. Uninitialised locations contain NOPs (`ADDI x0, x0, 0`).

### 4.2 Data Memory (dmem.sv)

The data memory is a byte-addressable SRAM implemented as a byte array. It supports word (LW/SW), halfword (LH/LHU/SH), and byte (LB/LBU/SB) accesses with configurable sign extension. Writes are synchronous; reads are combinational for single-cycle operation.

---

## 5. Peripheral Subsystem

### 5.1 GPIO (gpio.sv)

A 32-bit general-purpose I/O peripheral with five registers. Inputs pass through a double-synchroniser to handle asynchronous external signals. Rising-edge interrupts are supported on any pin, with a write-1-to-clear status register.

| Offset | Name     | Access | Description                       |
|--------|----------|--------|-----------------------------------|
| `0x00` | DATA_OUT | R/W    | Output data register              |
| `0x04` | DATA_IN  | RO     | Synchronised input pins           |
| `0x08` | DIR      | R/W    | Pin direction (1 = output)        |
| `0x0C` | IRQ_EN   | R/W    | Interrupt enable per pin          |
| `0x10` | IRQ_STAT | R/W1C  | Interrupt status (write-1-to-clear)|

### 5.2 UART (uart.sv)

A full-duplex UART peripheral supporting 8N1 framing with a configurable baud rate divider. The transmitter uses a shift-register state machine (IDLE → START → DATA → STOP). The receiver includes a double-synchroniser on the RX input and samples at mid-bit for noise immunity. Overrun detection is provided if new data arrives before the previous byte is read.

| Offset | Name    | Access | Description                              |
|--------|---------|--------|------------------------------------------|
| `0x00` | TX_DATA | WO     | Write byte to transmit                   |
| `0x04` | RX_DATA | RO     | Last received byte                       |
| `0x08` | STATUS  | RO     | [0] TX busy, [1] RX valid, [2] overrun   |
| `0x0C` | CTRL    | R/W    | [15:0] Baud divider                      |

**Baud rate calculation:** `baud = f_clk / (divider + 1)`

### 5.3 Timer (timer.sv)

A 32-bit counter with prescaler and auto-reload capability. When the counter reaches the compare value, a match flag is set (and optionally the counter reloads to zero). The prescaler allows the timer tick rate to be divided down from the system clock.

| Offset | Name      | Access | Description                        |
|--------|-----------|--------|------------------------------------|
| `0x00` | CTRL      | R/W    | [0] Enable, [1] Auto-reload       |
| `0x04` | PRESCALER | R/W    | Clock divider value                |
| `0x08` | COMPARE   | R/W    | Match / reload value               |
| `0x0C` | COUNT     | R/W    | Current counter value              |
| `0x10` | STATUS    | R/W1C  | [0] Match flag (write-1-to-clear)  |

---

## 6. Interrupt Architecture

The BRV32 supports two interrupt lines routed to the CSR unit:

- **MEIP** (Machine External Interrupt Pending, mip bit 11) — driven by the OR of GPIO and UART IRQs
- **MTIP** (Machine Timer Interrupt Pending, mip bit 7) — driven by the timer match flag

Interrupts are taken when the global MIE bit in mstatus is set and the corresponding bit in mie is enabled. On trap entry, the PC is redirected to the mtvec address, mepc saves the current PC, and mcause records the trap source. Interrupts are distinguished from exceptions by the MSB of mcause being set.

---

## 7. Module Hierarchy and RTL File Map

| File             | Module      | Description                           |
|------------------|-------------|---------------------------------------|
| `riscv_pkg.sv`   | *(package)* | Shared types, opcodes, memory map     |
| `brv32_mcu.sv`   | brv32_mcu   | SoC top-level with bus decoder        |
| `brv32_core.sv`  | brv32_core  | CPU core (PC, decode, execute, WB)    |
| `decoder.sv`     | decoder     | Instruction decoder + immediate gen   |
| `alu.sv`         | alu         | 32-bit arithmetic logic unit          |
| `regfile.sv`     | regfile     | 32×32 register file with forwarding   |
| `csr.sv`         | csr         | Control / Status Register unit        |
| `imem.sv`        | imem        | Instruction memory (ROM)              |
| `dmem.sv`        | dmem        | Data memory (SRAM)                    |
| `gpio.sv`        | gpio        | General-purpose I/O                   |
| `uart.sv`        | uart        | UART TX/RX (8N1)                      |
| `timer.sv`       | timer       | Timer/counter with prescaler          |

### Instantiation Hierarchy

```
brv32_mcu
├── brv32_core
│   ├── decoder
│   ├── regfile
│   ├── alu
│   └── csr
├── imem
├── dmem
├── gpio
├── uart
└── timer
```

---

## 8. Verification Strategy

### 8.1 Test Firmware

A 46-instruction test program (`firmware.hex`) is generated by a Python assembler script (`gen_firmware.py`). It exercises the critical execution paths: all ALU operations, load/store variants, conditional branches (BEQ, BNE), unconditional jumps (JAL, JALR), LUI, AUIPC, GPIO register writes, UART transmission, a BNE countdown loop, CSR read (mcycle), and finally an ECALL to verify trap handling.

### 8.2 SystemVerilog Testbench

The primary testbench (`tb_brv32_mcu.sv`) runs the test firmware and checks register file values, GPIO pin outputs, UART transmission, timer operation, and trap CSR fields at specific PC checkpoints. Features include:

- UART RX monitor task (captures transmitted bytes)
- GPIO interrupt testing via forced bus transactions
- Global timeout watchdog (500 µs)
- VCD waveform dumping (`+VCD` plusarg)
- Instruction tracing (`+TRACE` plusarg)

### 8.3 CocoTB Testbench

The CocoTB test suite (`test_brv32_mcu.py`) provides 15 independent test functions covering the same verification points as the SV testbench, plus some additional scenarios. Each test is self-contained with its own reset sequence, making it easy to run individual tests in isolation.

### 8.4 Test Coverage Summary

| Category       | Instructions / Features                              | Status |
|----------------|------------------------------------------------------|--------|
| ALU (R-type)   | ADD, SUB, SLT, SLTU, AND, OR, XOR, SLL, SRL, SRA   | Tested |
| ALU (I-type)   | ADDI, SLTI, SLTIU, ANDI, ORI, XORI, SLLI, SRLI, SRAI | Tested |
| Load/Store     | LW, LB, LBU, SW, SB                                 | Tested |
| Branches       | BEQ, BNE                                             | Tested |
| Jumps          | JAL, JALR                                            | Tested |
| Upper Imm      | LUI, AUIPC                                           | Tested |
| CSR            | CSRRS (mcycle read)                                  | Tested |
| Traps          | ECALL (mcause, mepc)                                 | Tested |
| GPIO           | Output, input sync, interrupt                        | Tested |
| UART           | TX, RX, baud config                                  | Tested |
| Timer          | Enable, match flag                                   | Tested |

---

## 9. Synthesis Considerations

The BRV32 is designed to be synthesisable on FPGA targets (Xilinx, Intel/Altera, Lattice). Key synthesis notes:

**ROM Initialisation.** The instruction memory uses `$readmemh` for initialisation, which is supported by all major FPGA synthesis tools. For ASIC targets, the ROM should be replaced with a mask-programmed ROM or a flash memory interface.

**Critical Path.** The single-cycle architecture means the critical path runs from instruction memory output through the decoder, register file read, ALU, data memory read, and writeback MUX. At 100 MHz on a modern FPGA (e.g. Artix-7), this path should close comfortably given the small decode logic.

**Reset Style.** All flip-flops use asynchronous active-low reset (`negedge rst_n`), which is standard for FPGA designs. For ASIC flows, synchronous reset may be preferred.

---

## 10. Future Enhancements

- **Pipeline:** A 5-stage pipeline (IF/ID/EX/MEM/WB) would significantly improve throughput at the cost of added complexity for hazard detection and forwarding.
- **M Extension:** Hardware multiply/divide (RV32IM) would enable efficient computation without software emulation routines.
- **C Extension:** Compressed 16-bit instructions (RV32IC) would reduce code size by approximately 25–30%, which is valuable for memory-constrained embedded targets.
- **DMA Controller:** A direct memory access engine would offload bulk data transfers from the CPU, enabling efficient peripheral I/O.
- **SPI/I2C Peripherals:** Additional communication interfaces would broaden the range of sensors and actuators the MCU can interact with.
- **Debug Module:** An on-chip debug unit conforming to the RISC-V Debug Specification would enable JTAG-based debugging with breakpoints and single-stepping.
