// ============================================================================
// tb_brv32_mcu.sv — Comprehensive Testbench for BRV32 MCU
// ============================================================================
// Tests:
//   1. Reset behaviour
//   2. ALU instructions (ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT)
//   3. Load/Store (LW, SW, LB, LBU, SB)
//   4. Branch instructions (BEQ, BNE)
//   5. JAL / JALR
//   6. LUI / AUIPC
//   7. GPIO peripheral read/write
//   8. UART TX transmission
//   9. Timer peripheral
//  10. CSR access (mcycle)
//  11. ECALL trap
// ============================================================================
`timescale 1ns / 1ps

module tb_brv32_mcu;

  // ── Clock & Reset ─────────────────────────────────────────────────
  logic        clk;
  logic        rst_n;
  logic [31:0] gpio_in;
  logic [31:0] gpio_out;
  logic        uart_rx;
  logic        uart_tx;

  // 100 MHz clock
  initial clk = 0;
  always #5 clk = ~clk;

  // ── DUT ───────────────────────────────────────────────────────────
  brv32_mcu #(
    .IMEM_DEPTH (256),
    .DMEM_DEPTH (256),
    .INIT_FILE  ("firmware.hex")
  ) dut (
    .clk      (clk),
    .rst_n    (rst_n),
    .gpio_in  (gpio_in),
    .gpio_out (gpio_out),
    .uart_rx  (uart_rx),
    .uart_tx  (uart_tx)
  );

  // ── Convenience: register file aliases ────────────────────────────
  // Access register file internals for checking
  `define REGFILE dut.u_core.u_regfile
  `define CORE    dut.u_core
  `define CSR     dut.u_core.u_csr
  `define GPIO    dut.u_gpio
  `define UART    dut.u_uart
  `define TIMER   dut.u_timer

  function automatic logic [31:0] get_reg(input int idx);
    if (idx == 0) return 32'd0;
    return `REGFILE.regs[idx];
  endfunction

  // ── Test infrastructure ───────────────────────────────────────────
  int pass_count = 0;
  int fail_count = 0;
  int test_num   = 0;

  task automatic check(input string name, input logic [31:0] actual, input logic [31:0] expected);
    test_num++;
    if (actual === expected) begin
      $display("[PASS] #%0d %s: 0x%08h", test_num, name, actual);
      pass_count++;
    end else begin
      $display("[FAIL] #%0d %s: got 0x%08h, expected 0x%08h", test_num, name, actual, expected);
      fail_count++;
    end
  endtask

  task automatic check_bit(input string name, input logic actual, input logic expected);
    test_num++;
    if (actual === expected) begin
      $display("[PASS] #%0d %s: %0b", test_num, name, actual);
      pass_count++;
    end else begin
      $display("[FAIL] #%0d %s: got %0b, expected %0b", test_num, name, actual, expected);
      fail_count++;
    end
  endtask

  // Wait for PC to reach a specific address
  task automatic wait_pc(input logic [31:0] target_pc, input int timeout = 5000);
    int count = 0;
    while (`CORE.pc !== target_pc && count < timeout) begin
      @(posedge clk);
      count++;
    end
    if (count >= timeout)
      $display("[WARN] Timeout waiting for PC = 0x%08h (stuck at 0x%08h)", target_pc, `CORE.pc);
  endtask

  // Run for N cycles
  task automatic run_cycles(input int n);
    repeat(n) @(posedge clk);
  endtask

  // ── UART RX Monitor ───────────────────────────────────────────────
  logic [7:0] uart_rx_byte;
  logic       uart_rx_valid;

  task automatic uart_monitor();
    int baud_period;
    baud_period = (8 + 1) * 10; // divider=8, 10ns per clock
    forever begin
      uart_rx_valid = 0;
      @(negedge uart_tx); // Wait for start bit
      #(baud_period * 1.5); // Move to middle of first data bit
      for (int i = 0; i < 8; i++) begin
        uart_rx_byte[i] = uart_tx;
        #(baud_period);
      end
      uart_rx_valid = 1;
      $display("[UART] Received byte: 0x%02h ('%c')", uart_rx_byte, uart_rx_byte);
      @(posedge clk);
    end
  endtask

  // ── Main Test Sequence ────────────────────────────────────────────
  initial begin
    $display("============================================================");
    $display("  BRV32 MCU — Comprehensive Testbench");
    $display("============================================================");

    // ── Initialise ──────────────────────────────────────────────────
    rst_n   = 0;
    gpio_in = 32'h0000_0000;
    uart_rx = 1'b1; // Idle high

    // Fork UART monitor
    fork
      uart_monitor();
    join_none

    // ── Test 1: Reset ───────────────────────────────────────────────
    $display("\n--- Test Group: Reset ---");
    repeat(5) @(posedge clk);
    check("PC after reset", `CORE.pc, 32'h0000_0000);

    // Release reset
    @(posedge clk);
    rst_n = 1;

    // ── Test 2: ALU Instructions ────────────────────────────────────
    $display("\n--- Test Group: ALU Instructions ---");
    // Wait for all ALU instructions to complete (up to 0x28)
    wait_pc(32'h0000_002C);

    check("ADDI x1, x0, 42",      get_reg(1), 32'd42);
    check("ADDI x2, x0, 10",      get_reg(2), 32'd10);
    check("ADD  x3, x1, x2",      get_reg(3), 32'd52);
    check("SUB  x4, x1, x2",      get_reg(4), 32'd32);
    check("ANDI x5, x3, 0xFF",    get_reg(5), 32'd52);
    check("ORI  x6, x0, 0x55",    get_reg(6), 32'h55);
    check("XORI x7, x6, 0xFF",    get_reg(7), 32'hAA);
    check("SLLI x8, x2, 4",       get_reg(8), 32'd160);
    check("SRLI x9, x8, 2",       get_reg(9), 32'd40);
    check("SLTI x18, x4, 100",    get_reg(18), 32'd1);
    check("SLT  x19, x2, x1",     get_reg(19), 32'd1);

    // ── Test 3: Load/Store ──────────────────────────────────────────
    $display("\n--- Test Group: Load/Store ---");
    wait_pc(32'h0000_0040);

    check("LUI  x10 = DMEM base",  get_reg(10), 32'h1000_0000);
    check("LW   x11 from DMEM[0]", get_reg(11), 32'd52);
    check("LBU  x12 from DMEM[4]", get_reg(12), 32'h55);

    // ── Test 4: GPIO ────────────────────────────────────────────────
    $display("\n--- Test Group: GPIO ---");
    wait_pc(32'h0000_0050);

    check("GPIO DIR",  `GPIO.dir, 32'h0000_00FF);
    check("GPIO OUT",  `GPIO.data_out, 32'd52);
    check("gpio_out pin", gpio_out[7:0], 8'd52);

    // Test GPIO input
    gpio_in = 32'hDEAD_BEEF;
    run_cycles(5); // Allow sync
    check("GPIO input sync", `GPIO.gpio_in_sync, 32'hDEAD_BEEF);

    // ── Test 5: Branch (BEQ, BNE) ───────────────────────────────────
    $display("\n--- Test Group: Branches ---");
    wait_pc(32'h0000_0068);

    // After BEQ: x15 should be 1 (took branch, skipped 0xDE)
    // After BNE: x15 should be 2 (took branch, skipped 0xDE)
    check("BEQ taken → x15=1 then BNE → x15=2", get_reg(15), 32'd2);

    // ── Test 6: JAL ─────────────────────────────────────────────────
    $display("\n--- Test Group: JAL / JALR ---");
    wait_pc(32'h0000_0078);

    check("JAL link register x16",  get_reg(16), 32'h0000_006C);
    check("JAL target: x17=3",      get_reg(17), 32'd3);

    // ── Test 7: UART ────────────────────────────────────────────────
    $display("\n--- Test Group: UART ---");
    wait_pc(32'h0000_0098);

    // UART TX should start transmitting 'H' (0x48)
    // Wait for transmission to complete
    run_cycles(200);
    check_bit("UART TX busy after send", `UART.tx_busy, 1'b1);

    // Wait for TX to finish
    run_cycles(200);

    // ── Test 8: Wait loop (BNE countdown) ───────────────────────────
    $display("\n--- Test Group: Loop ---");
    // The loop runs 100 iterations. Wait for it.
    wait_pc(32'h0000_00A4, 10000);
    check("Loop counter x23=0", get_reg(23), 32'd0);

    // ── Test 9: AUIPC ───────────────────────────────────────────────
    $display("\n--- Test Group: AUIPC ---");
    wait_pc(32'h0000_00A8);
    check("AUIPC x20 = PC", get_reg(20), 32'h0000_00A4);

    // ── Test 10: CSR mcycle ─────────────────────────────────────────
    $display("\n--- Test Group: CSR ---");
    wait_pc(32'h0000_00AC);
    // mcycle should be non-zero after many cycles
    if (get_reg(21) != 32'd0) begin
      $display("[PASS] #%0d CSR mcycle read nonzero: 0x%08h", test_num+1, get_reg(21));
      pass_count++;
    end else begin
      $display("[FAIL] #%0d CSR mcycle read: expected nonzero, got 0", test_num+1);
      fail_count++;
    end
    test_num++;

    // ── Test 11: ECALL trap ─────────────────────────────────────────
    $display("\n--- Test Group: ECALL Trap ---");
    run_cycles(5);
    check("mcause = 11 (ecall M-mode)", `CSR.mcause, 32'd11);
    check("mepc = ecall PC", `CSR.mepc, 32'h0000_00AC);

    // ── Test 12: Timer Peripheral ───────────────────────────────────
    $display("\n--- Test Group: Timer Direct ---");
    // Directly poke timer registers through the bus
    // Since the CPU is trapped, we can force bus transactions
    force dut.u_core.dmem_addr = 32'h2000_0208; // COMPARE
    force dut.u_core.dmem_wr_en = 1'b1;
    force dut.u_core.dmem_wdata = 32'd5;
    @(posedge clk);
    force dut.u_core.dmem_addr = 32'h2000_0200; // CTRL: enable + auto-reload
    force dut.u_core.dmem_wdata = 32'h0000_0003;
    @(posedge clk);
    release dut.u_core.dmem_addr;
    release dut.u_core.dmem_wr_en;
    release dut.u_core.dmem_wdata;

    // Wait for timer to fire
    run_cycles(20);
    check_bit("Timer match flag", `TIMER.match_flag, 1'b1);

    // ── Test 13: GPIO Interrupt ─────────────────────────────────────
    $display("\n--- Test Group: GPIO Interrupt ---");
    // Enable GPIO interrupt on pin 0
    force dut.u_core.dmem_addr = 32'h2000_000C; // IRQ_EN
    force dut.u_core.dmem_wr_en = 1'b1;
    force dut.u_core.dmem_wdata = 32'h0000_0001;
    @(posedge clk);
    release dut.u_core.dmem_addr;
    release dut.u_core.dmem_wr_en;
    release dut.u_core.dmem_wdata;

    // Generate rising edge on gpio_in[0]
    gpio_in[0] = 0;
    run_cycles(5);
    gpio_in[0] = 1;
    run_cycles(5);
    check_bit("GPIO IRQ asserted", `GPIO.irq, 1'b1);

    // ── Test 14: UART RX ────────────────────────────────────────────
    $display("\n--- Test Group: UART RX ---");
    // Send a byte to UART RX (0x41 = 'A')
    // Baud: divider = 8 → 9 clocks per bit
    begin
      int bit_period;
      bit_period = 9; // clk cycles per UART bit (divider + 1)
      uart_rx = 1'b0; // Start bit
      repeat(bit_period) @(posedge clk);
      // Data bits LSB first: 0x41 = 0100_0001
      for (int i = 0; i < 8; i++) begin
        uart_rx = (8'h41 >> i) & 1;
        repeat(bit_period) @(posedge clk);
      end
      uart_rx = 1'b1; // Stop bit
      repeat(bit_period) @(posedge clk);
      run_cycles(5);
    end
    check("UART RX data", `UART.rx_data, 8'h41);
    check_bit("UART RX valid", `UART.rx_valid, 1'b1);

    // ── Summary ─────────────────────────────────────────────────────
    $display("\n============================================================");
    $display("  Test Results: %0d PASSED, %0d FAILED out of %0d",
             pass_count, fail_count, test_num);
    if (fail_count == 0)
      $display("  *** ALL TESTS PASSED ***");
    else
      $display("  *** SOME TESTS FAILED ***");
    $display("============================================================");

    $finish;
  end

  // ── Timeout watchdog ──────────────────────────────────────────────
  initial begin
    #500_000;
    $display("[ERROR] Global timeout — simulation stuck!");
    $finish;
  end

  // ── Optional: VCD dump ────────────────────────────────────────────
  initial begin
    if ($test$plusargs("VCD")) begin
      $dumpfile("brv32_mcu.vcd");
      $dumpvars(0, tb_brv32_mcu);
    end
  end

  // ── PC trace (optional, for debug) ────────────────────────────────
  initial begin
    if ($test$plusargs("TRACE")) begin
      forever begin
        @(posedge clk);
        if (rst_n)
          $display("[TRACE] PC=0x%08h INSTR=0x%08h", `CORE.pc, `CORE.instr);
      end
    end
  end

endmodule
