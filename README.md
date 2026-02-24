# BRV32 — RISC-V RV32I Microcontroller

A single-cycle RV32I microcontroller SoC with GPIO, UART, and Timer peripherals.

## Directory Structure
```
brv32_mcu/
├── rtl/                    # SystemVerilog RTL source files
│   ├── riscv_pkg.sv        # Shared package (opcodes, types, memory map)
│   ├── alu.sv              # 32-bit ALU
│   ├── regfile.sv          # 32x32 Register File
│   ├── decoder.sv          # Instruction Decoder
│   ├── imem.sv             # Instruction Memory (ROM)
│   ├── dmem.sv             # Data Memory (SRAM)
│   ├── csr.sv              # Control/Status Registers
│   ├── gpio.sv             # GPIO Peripheral
│   ├── uart.sv             # UART Peripheral (8N1)
│   ├── timer.sv            # Timer/Counter Peripheral
│   ├── brv32_core.sv       # CPU Core
│   └── brv32_mcu.sv        # SoC Top-Level
├── tb/                     # SystemVerilog Testbench
│   └── tb_brv32_mcu.sv
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

## Running the SystemVerilog Testbench
```bash
cd tb
# With Icarus Verilog:
iverilog -g2012 -o sim ../rtl/riscv_pkg.sv ../rtl/alu.sv ../rtl/regfile.sv \
  ../rtl/decoder.sv ../rtl/imem.sv ../rtl/dmem.sv ../rtl/gpio.sv \
  ../rtl/uart.sv ../rtl/timer.sv ../rtl/csr.sv ../rtl/brv32_core.sv \
  ../rtl/brv32_mcu.sv tb_brv32_mcu.sv
cp ../firmware/firmware.hex .
vvp sim +VCD    # Optional: +TRACE for instruction trace
```

## Running the CocoTB Testbench
```bash
cd cocotb
cp ../firmware/firmware.hex .
make            # Run all tests
make TESTCASE=test_01_reset  # Run a single test
make WAVES=1    # Dump waveforms
```
