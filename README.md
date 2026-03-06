# BRV32 — Single-Cycle RV32I RISC-V Microcontroller

A complete, synthesisable single-cycle RV32I RISC-V SoC written in **Verilog-2001**. Integrates a CPU core with instruction and data memories, GPIO, UART, and Timer peripherals. Verified with both a SystemVerilog testbench (Icarus Verilog) and a Python CocoTB suite. 32/32 tests passing.

---

## Features

| Category | Detail |
|---|---|
| **ISA** | RV32I — full Base Integer instruction set |
| **Architecture** | Single-cycle (one instruction retired per clock) |
| **RTL language** | Verilog-2001 — `reg`/`wire`, `always @(*)`, `always @(posedge clk)` |
| **Instruction memory** | Synchronous ROM (`imem.v`), loaded from `firmware.hex` |
| **Data memory** | Single-cycle SRAM (`dmem.v`), byte/halfword/word access |
| **Peripherals** | GPIO (with interrupts), UART 8N1 TX/RX, Timer/counter |
| **CSRs** | Machine-mode subset: `mstatus`, `mie`, `mip`, `mepc`, `mcause`, `mtvec`, `mcycle`, `minstret` |
| **Simulator** | Icarus Verilog v10+ (`-g2012` for SV testbench; RTL itself is Verilog-2001) |
| **Test framework** | Native Verilog TB + CocoTB Python suite |

---

## Architecture Overview

```
                   ┌─────────────────────────────┐
                   │         BRV32 MCU            │
                   │                              │
  clk ────────────►│  ┌────────────────────────┐  │◄──► GPIO[31:0]
  rst_n ──────────►│  │      brv32_core        │  │◄──► uart_rx / uart_tx
                   │  │                        │  │◄──► timer_irq
                   │  │  PC ──► imem ──► dec   │  │
                   │  │         alu             │  │
                   │  │         regfile         │  │
                   │  │         csr             │  │
                   │  │           │             │  │
                   │  └───────────┼─────────────┘  │
                   │             │                  │
                   │  ┌──────────▼──────────────┐  │
                   │  │  dmem / gpio / uart /   │  │
                   │  │  timer  (addr-decoded)  │  │
                   │  └─────────────────────────┘  │
                   └─────────────────────────────┘
```

In a single-cycle design every combinatorial path — fetch → decode → execute → memory → write-back — completes within one clock period. The clock period is therefore bounded by the longest path through the datapath (typically a load instruction traversing the ALU, dmem, and write-back mux).

---

## Memory Map

| Address Range | Size | Description |
|---|---|---|
| `0x0000_0000` – `0x0000_3FFF` | 16 KB | Instruction memory (ROM) |
| `0x0001_0000` – `0x0001_3FFF` | 16 KB | Data memory (SRAM) |
| `0x1000_0000` – `0x1000_00FF` | 256 B | GPIO registers |
| `0x1000_0100` – `0x1000_01FF` | 256 B | UART registers |
| `0x1000_0200` – `0x1000_02FF` | 256 B | Timer registers |

---

## Directory Structure

```
RISCV_RV32I_SingleCycle/
├── rtl/
│   ├── brv32_defines.vh    # Shared `define macros (opcodes, ALU ops, CSR addresses)
│   ├── alu.v               # 32-bit ALU (all RV32I operations)
│   ├── regfile.v           # 32 × 32-bit register file (x0 hardwired to 0)
│   ├── decoder.v           # Instruction decoder → control signals
│   ├── imem.v              # Instruction memory (ROM, $readmemh)
│   ├── dmem.v              # Data memory (SRAM, byte/halfword/word)
│   ├── csr.v               # Machine-mode CSRs
│   ├── gpio.v              # GPIO with interrupt support
│   ├── uart.v              # UART TX / RX (8N1)
│   ├── timer.v             # Timer / counter with compare interrupt
│   ├── brv32_core.v        # CPU core (datapath + control)
│   └── brv32_mcu.v         # SoC top-level (core + memories + peripherals)
├── tb/
│   └── tb_brv32_mcu.v      # SystemVerilog testbench (Icarus -g2012)
├── cocotb/
│   ├── test_brv32_mcu.py   # CocoTB Python test suite
│   └── Makefile
├── firmware/
│   ├── firmware.hex        # Pre-assembled firmware image ($readmemh format)
│   └── gen_firmware.py     # Python assembler / firmware generator
└── doc/
    ├── BRV32_Design_Report.md
    ├── BRV32_Design_Report.pdf
    └── BRV32_Design_Report.docx
```

---

## Prerequisites

### Simulation

```bash
sudo apt install iverilog          # Ubuntu / Debian
brew install icarus-verilog        # macOS
```

Minimum version: **Icarus Verilog 10** (Ubuntu 18.04 default). v12 also tested.

> The RTL uses only Verilog-2001 constructs and is compatible with `-g2005` or `-g2012`.
> The testbench (`tb_brv32_mcu.v`) uses SystemVerilog syntax and requires `-g2012`.

### CocoTB

```bash
pip install cocotb
```

CocoTB uses Icarus Verilog as its backend via the `Makefile`.

### Firmware toolchain (optional — pre-built hex included)

```bash
# Ubuntu 20.04+
sudo apt install gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf

# Then regenerate firmware:
cd firmware && python gen_firmware.py
```

---

## Running Tests

### Icarus Verilog testbench

```bash
cd tb
iverilog -g2012 -I ../rtl -o sim \
  ../rtl/alu.v ../rtl/regfile.v ../rtl/decoder.v \
  ../rtl/imem.v ../rtl/dmem.v ../rtl/gpio.v \
  ../rtl/uart.v ../rtl/timer.v ../rtl/csr.v \
  ../rtl/brv32_core.v ../rtl/brv32_mcu.v \
  tb_brv32_mcu.v
cp ../firmware/firmware.hex .
vvp sim
```

Expected output: `32/32 tests PASSED`

### CocoTB

```bash
cd cocotb
cp ../firmware/firmware.hex .
make                              # Run all tests
make TESTCASE=test_01_reset       # Run a single test
make WAVES=1                      # Dump VCD waveforms
```

---

## Design Notes

### Single-cycle datapath

Every instruction completes in a single clock cycle. The datapath is purely combinatorial between register-file read and write-back. The clock period must accommodate the worst-case path, which for a load instruction is:

```
PC-reg → imem → decoder → ALU → dmem → write-back mux → regfile setup
```

This makes the design straightforward to understand and verify, but limits achievable clock frequency compared to a pipelined implementation.

### Register file

`x0` is hardwired to zero; writes to `x0` are silently discarded. The register file uses **read-after-write** ordering: if a write and a read to the same address occur in the same cycle, the read returns the old value (i.e., there is no write-first bypass). This is correct in a single-cycle implementation because write-back and the next fetch are logically sequential, and avoids a combinational loop through `gpio_in_sync → rdata → dmem_rdata → rs1_data → alu_result → dmem_addr`.

### Peripheral addressing

The SoC top-level (`brv32_mcu.v`) decodes the upper address bits to route memory-mapped I/O to the appropriate peripheral. Peripheral reads return their register value combinatorially; writes are registered on the rising edge.

### Instruction and data memories

`imem.v` uses `$readmemh` to load `firmware.hex` at elaboration time. `dmem.v` supports byte (`LB`/`SB`), halfword (`LH`/`SH`), and word (`LW`/`SW`) accesses with sign extension for loads. Both memories are synchronous with a read latency of one cycle — which in a single-cycle design means read data is available at the combinatorial output in the same cycle as the address (the memory model is behavioural and infers combinatorial reads for simulation).

---

## Known Limitations

- No pipeline — throughput is limited by the critical path delay
- No cache — instruction and data memories are directly accessed each cycle
- No virtual memory or privilege levels below Machine mode
- UART baud rate is fixed at elaboration time (configured in `brv32_defines.vh`)
- No DMA; peripheral access is polled or interrupt-driven
- No formal verification; compliance tested via directed testbenches only

---

## Documentation

See [`doc/BRV32_Design_Report.md`](doc/BRV32_Design_Report.md) for a full micro-architecture description including the datapath diagram, control signal table, CSR register map, peripheral register maps, and testbench methodology.

---

## Licence

MIT
