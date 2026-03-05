// ============================================================================
// tb_brv32_mcu.v — BRV32 MCU Testbench (Verilog-2001, iverilog v10+)
// Uses run_cycles-based sequencing (no wait_pc) for reliable simulation.
// ============================================================================
`timescale 1ns / 1ps

module tb_brv32_mcu;

  reg         clk;
  reg         rst_n;
  reg  [31:0] gpio_in;
  wire [31:0] gpio_out;
  reg         uart_rx;
  wire        uart_tx;

  initial clk = 0;
  always #5 clk = ~clk;

  brv32_mcu #(
    .IMEM_DEPTH (256),
    .DMEM_DEPTH (256),
    .INIT_FILE  ("../firmware/firmware.hex")
  ) dut (
    .clk(clk), .rst_n(rst_n),
    .gpio_in(gpio_in), .gpio_out(gpio_out),
    .uart_rx(uart_rx), .uart_tx(uart_tx)
  );

  `define REGFILE dut.u_core.u_regfile
  `define CORE    dut.u_core
  `define CSR     dut.u_core.u_csr
  `define GPIO    dut.u_gpio
  `define UART    dut.u_uart
  `define TIMER   dut.u_timer

  integer pass_count, fail_count, test_num, k, i;

  task check;
    input [127:0] label;
    input [31:0]  actual;
    input [31:0]  expected;
    begin
      test_num = test_num + 1;
      if (actual === expected) begin
        $display("[PASS] #%0d %s: 0x%08h", test_num, label, actual);
        pass_count = pass_count + 1;
      end else begin
        $display("[FAIL] #%0d %s: got 0x%08h exp 0x%08h", test_num, label, actual, expected);
        fail_count = fail_count + 1;
      end
    end
  endtask

  task check_bit;
    input [127:0] label;
    input         actual;
    input         expected;
    begin
      test_num = test_num + 1;
      if (actual === expected) begin
        $display("[PASS] #%0d %s: %0b", test_num, label, actual);
        pass_count = pass_count + 1;
      end else begin
        $display("[FAIL] #%0d %s: got %0b exp %0b", test_num, label, actual, expected);
        fail_count = fail_count + 1;
      end
    end
  endtask

  task run_cycles;
    input integer n;
    integer c;
    begin
      for (c = 0; c < n; c = c + 1)
        @(posedge clk);
    end
  endtask

  initial begin
    pass_count = 0; fail_count = 0; test_num = 0;
    rst_n = 1'b0; gpio_in = 32'h0; uart_rx = 1'b1;

    $display("============================================================");
    $display("  BRV32 MCU -- Testbench (iverilog v10 compatible)");
    $display("============================================================");

    // ── Reset ────────────────────────────────────────────────────────
    $display("\n--- Reset ---");
    repeat(3) @(posedge clk);
    check("PC after reset", `CORE.pc, 32'h0);
    @(posedge clk);
    rst_n = 1'b1;

    // ── ALU: 11 instrs to reach 0x002C ───────────────────────────────
    $display("\n--- ALU Instructions ---");
    run_cycles(13); // +2 margin
    check("ADDI x1,x0,42",   `REGFILE.regs[1],  32'd42);
    check("ADDI x2,x0,10",   `REGFILE.regs[2],  32'd10);
    check("ADD  x3,x1,x2",   `REGFILE.regs[3],  32'd52);
    check("SUB  x4,x1,x2",   `REGFILE.regs[4],  32'd32);
    check("ANDI x5,x3,0xFF", `REGFILE.regs[5],  32'd52);
    check("ORI  x6,x0,0x55", `REGFILE.regs[6],  32'h55);
    check("XORI x7,x6,0xFF", `REGFILE.regs[7],  32'hAA);
    check("SLLI x8,x2,4",    `REGFILE.regs[8],  32'd160);
    check("SRLI x9,x8,2",    `REGFILE.regs[9],  32'd40);
    check("SLTI x18,x4,100", `REGFILE.regs[18], 32'd1);
    check("SLT  x19,x2,x1",  `REGFILE.regs[19], 32'd1);

    // ── Load/Store: 5 instrs 0x002C→0x0040 ───────────────────────────
    $display("\n--- Load/Store ---");
    run_cycles(7);
    check("LUI  x10=DMEM",  `REGFILE.regs[10], 32'h1000_0000);
    check("LW   x11 [0]",   `REGFILE.regs[11], 32'd52);
    check("LBU  x12 [4]",   `REGFILE.regs[12], 32'h55);

    // ── GPIO: 4 instrs 0x0040→0x0050, then branch block ─────────────
    $display("\n--- GPIO ---");
    run_cycles(6);
    check("GPIO DIR",      `GPIO.dir,      32'h0000_00FF);
    check("GPIO OUT",      `GPIO.data_out, 32'd52);
    check("gpio_out[7:0]", {24'b0,gpio_out[7:0]}, {24'b0,8'd52});
    gpio_in = 32'hDEAD_BEEF;
    run_cycles(5); // 2 sync stages + margin
    check("GPIO in sync",  `GPIO.gpio_in_sync, 32'hDEAD_BEEF);

    // ── Branches: 8 instrs 0x0050→0x0070 (includes taken branches) ───
    $display("\n--- Branches ---");
    run_cycles(10);
    check("BEQ+BNE x15=2", `REGFILE.regs[15], 32'd2);

    // ── JAL/JALR: 2 instrs 0x0070→0x0078 ────────────────────────────
    $display("\n--- JAL / JALR ---");
    run_cycles(4);
    check("JAL link x16",  `REGFILE.regs[16], 32'h0000_006C);
    check("JALR x17=3",    `REGFILE.regs[17], 32'd3);

    // ── UART TX: 8 instrs 0x0078→0x0098, div=8 so TX takes 90 cycles ─
    $display("\n--- UART TX ---");
    run_cycles(10); // reach 0x0098 (writes TX at 0x0094)
    run_cycles(20); // let tx_busy assert (TX_IDLE→TX_START in ~1 cycle)
    check_bit("UART TX busy", `UART.tx_busy, 1'b1);
    run_cycles(200); // finish TX (90 cycles needed)

    // ── Loop: 3 instrs 0x0098→0x00A4, loop runs 5 times ─────────────
    $display("\n--- Loop ---");
    run_cycles(20); // 5 iterations * 2 instrs each + ADDI = ~15 cycles
    check("Loop x23=0", `REGFILE.regs[23], 32'd0);

    // ── AUIPC ─────────────────────────────────────────────────────────
    $display("\n--- AUIPC ---");
    check("AUIPC x20=0xA4", `REGFILE.regs[20], 32'h0000_00A4);

    // ── CSR mcycle ────────────────────────────────────────────────────
    $display("\n--- CSR ---");
    run_cycles(4);
    test_num = test_num + 1;
    if (`REGFILE.regs[21] != 32'd0) begin
      $display("[PASS] #%0d CSR mcycle=0x%08h", test_num, `REGFILE.regs[21]);
      pass_count = pass_count + 1;
    end else begin
      $display("[FAIL] #%0d CSR mcycle=0", test_num);
      fail_count = fail_count + 1;
    end

    // ── ECALL trap ────────────────────────────────────────────────────
    $display("\n--- ECALL Trap ---");
    run_cycles(4);
    check("mcause=11",  `CSR.mcause, 32'd11);
    check("mepc=ecall", `CSR.mepc,   32'h0000_00AC);

    // ── Timer (force peripheral bus directly) ────────────────────────
    $display("\n--- Timer ---");
    // Write COMPARE=5 then CTRL=enable+autoreload via timer's own ports
    force dut.u_timer.addr   = 8'h08; // COMPARE offset
    force dut.u_timer.wr_en  = 1'b1;
    force dut.u_timer.wdata  = 32'd5;
    @(posedge clk);
    force dut.u_timer.addr   = 8'h00; // CTRL offset
    force dut.u_timer.wdata  = 32'h0000_0003;
    @(posedge clk);
    release dut.u_timer.addr;
    release dut.u_timer.wr_en;
    release dut.u_timer.wdata;
    run_cycles(20);
    check_bit("Timer match", `TIMER.match_flag, 1'b1);

    // ── GPIO IRQ (force peripheral bus directly) ──────────────────────
    $display("\n--- GPIO IRQ ---");
    force dut.u_gpio.addr   = 8'h0C; // IRQ_EN offset
    force dut.u_gpio.wr_en  = 1'b1;
    force dut.u_gpio.wdata  = 32'h0000_0001;
    @(posedge clk);
    release dut.u_gpio.addr;
    release dut.u_gpio.wr_en;
    release dut.u_gpio.wdata;
    gpio_in[0] = 1'b0; run_cycles(5);
    gpio_in[0] = 1'b1; run_cycles(5);
    check_bit("GPIO IRQ", `GPIO.irq, 1'b1);

    // ── UART RX ───────────────────────────────────────────────────────
    $display("\n--- UART RX ---");
    begin : uart_rx_blk
      integer bit_p;
      bit_p = 9;
      uart_rx = 1'b0; run_cycles(bit_p);
      for (i = 0; i < 8; i = i + 1) begin
        uart_rx = (8'h41 >> i) & 1'b1;
        run_cycles(bit_p);
      end
      uart_rx = 1'b1; run_cycles(bit_p);
      run_cycles(5);
    end
    check("UART RX data",      {24'b0,`UART.rx_data}, {24'b0,8'h41});
    check_bit("UART RX valid", `UART.rx_valid,        1'b1);

    // ── Summary ───────────────────────────────────────────────────────
    $display("\n============================================================");
    $display("  Results: %0d PASSED, %0d FAILED / %0d total",
             pass_count, fail_count, test_num);
    if (fail_count == 0) $display("  *** ALL TESTS PASSED ***");
    else                 $display("  *** SOME TESTS FAILED ***");
    $display("============================================================");
    $finish;
  end

  initial begin
    #5_000_000;
    $display("[ERROR] Watchdog timeout!");
    $finish;
  end

  initial begin
    if ($test$plusargs("VCD")) begin
      $dumpfile("brv32_mcu.vcd");
      $dumpvars(0, tb_brv32_mcu);
    end
  end

  always @(posedge clk) begin
    if (rst_n && $test$plusargs("TRACE"))
      $display("[TRACE] PC=0x%08h INSTR=0x%08h", `CORE.pc, `CORE.instr);
  end

endmodule
