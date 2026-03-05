# BRV32 — RISC-V RV32I Microcontroller

A single-cycle RV32I microcontroller SoC with GPIO, UART, and Timer peripherals.

## Directory Structure
```
brv32_mcu/
├── rtl/                    # SystemVerilog RTL source files
│   ├── brv32_defines.vh    # Shared defines (opcodes, ALU ops, CSR addresses)
│   ├── alu.v              # 32-bit ALU
│   ├── regfile.v          # 32x32 Register File
│   ├── decoder.v          # Instruction Decoder
│   ├── imem.v             # Instruction Memory (ROM)
│   ├── dmem.v             # Data Memory (SRAM)
│   ├── csr.v              # Control/Status Registers
│   ├── gpio.v             # GPIO Peripheral
│   ├── uart.v             # UART Peripheral (8N1)
│   ├── timer.v            # Timer/Counter Peripheral
│   ├── brv32_core.v       # CPU Core
│   └── brv32_mcu.v        # SoC Top-Level
├── tb/                     # SystemVerilog Testbench
│   └── tb_brv32_mcu.v
├── cocotb/                 # CocoTB Python Testbench
│   ├── test_brv32_mcu.py
│   └── Makefile
├── firmware/               # Test firmware
│   ├── firmware.hex         # Pre-assembled hex file
│   └── gen_firmware.py      # Python assembler script
└── doc/
    └── BRV32_Design_Report.docx
    └── BRV32_Design_Report.md
    └── BRV32_Design_Report.pdf
```

## Running the Testbench

Tested with **Icarus Verilog v10** (Ubuntu 18.04 default) and v12.

```bash
cd tb
iverilog -g2012 -I../rtl -o sim \
  ../rtl/alu.v ../rtl/regfile.v ../rtl/decoder.v \
  ../rtl/imem.v ../rtl/dmem.v ../rtl/gpio.v \
  ../rtl/uart.v ../rtl/timer.v ../rtl/csr.v \
  ../rtl/brv32_core.v ../rtl/brv32_mcu.v \
  tb_brv32_mcu.v
vvp sim
```

> **Note:** `-g2012` is required for the SV testbench. The RTL itself uses
> only Verilog-2001 constructs (`reg`/`wire`, `always @(*)`, `always @(posedge clk)`).
> The include path `-I../rtl` resolves `brv32_defines.vh`.

## Running the CocoTB Testbench
```bash
cd cocotb
cp ../firmware/firmware.hex .
make            # Run all tests
make TESTCASE=test_01_reset  # Run a single test
make WAVES=1    # Dump waveforms
```
