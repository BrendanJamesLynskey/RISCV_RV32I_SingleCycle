// ============================================================================
// brv32_mcu.sv — BRV32 SoC Top-Level (Verilog-2001)
// Memory Map: 0x0000_0000 IMEM | 0x1000_0000 DMEM
//             0x2000_0000 GPIO | 0x2000_0100 UART | 0x2000_0200 TIMER
// ============================================================================
`include "brv32_defines.vh"

module brv32_mcu #(
  parameter IMEM_DEPTH = 256,
  parameter DMEM_DEPTH = 1024,
  parameter INIT_FILE  = "firmware.hex"
)(
  input         clk,
  input         rst_n,
  input  [31:0] gpio_in,
  output [31:0] gpio_out,
  input         uart_rx,
  output        uart_tx
);
  wire [31:0] imem_addr, imem_rdata;
  wire [31:0] dmem_addr, dmem_wdata;
  wire        dmem_rd_en, dmem_wr_en;
  wire [1:0]  dmem_width;
  wire        dmem_sign_ext;
  reg  [31:0] dmem_rdata;

  wire [31:0] dmem_mem_rdata, gpio_rdata, uart_rdata, timer_rdata;
  wire        gpio_irq, uart_irq, timer_irq;

  wire sel_dmem  = (dmem_addr[31:28] == 4'h1);
  wire sel_gpio  = (dmem_addr[31:8]  == 24'h200000);
  wire sel_uart  = (dmem_addr[31:8]  == 24'h200001);
  wire sel_timer = (dmem_addr[31:8]  == 24'h200002);

  always @(*) begin
    if      (sel_gpio)  dmem_rdata = gpio_rdata;
    else if (sel_uart)  dmem_rdata = uart_rdata;
    else if (sel_timer) dmem_rdata = timer_rdata;
    else                dmem_rdata = dmem_mem_rdata;
  end

  brv32_core u_core (
    .clk(clk),             .rst_n(rst_n),
    .imem_addr(imem_addr), .imem_rdata(imem_rdata),
    .dmem_addr(dmem_addr), .dmem_rd_en(dmem_rd_en),
    .dmem_wr_en(dmem_wr_en),.dmem_width(dmem_width),
    .dmem_sign_ext(dmem_sign_ext),
    .dmem_wdata(dmem_wdata),.dmem_rdata(dmem_rdata),
    .ext_irq(gpio_irq | uart_irq), .timer_irq(timer_irq)
  );

  imem #(.DEPTH(IMEM_DEPTH), .INIT_FILE(INIT_FILE)) u_imem (
    .addr(imem_addr), .rdata(imem_rdata)
  );

  dmem #(.DEPTH(DMEM_DEPTH)) u_dmem (
    .clk(clk),        .rst_n(rst_n),
    .addr(dmem_addr), .rd_en(dmem_rd_en & sel_dmem),
    .wr_en(dmem_wr_en & sel_dmem), .width(dmem_width),
    .sign_ext(dmem_sign_ext),
    .wdata(dmem_wdata), .rdata(dmem_mem_rdata)
  );

  gpio u_gpio (
    .clk(clk),        .rst_n(rst_n),
    .addr(dmem_addr[7:0]),
    .wr_en(dmem_wr_en & sel_gpio), .rd_en(dmem_rd_en & sel_gpio),
    .wdata(dmem_wdata), .rdata(gpio_rdata),
    .gpio_in(gpio_in), .gpio_out(gpio_out), .irq(gpio_irq)
  );

  uart u_uart (
    .clk(clk),        .rst_n(rst_n),
    .addr(dmem_addr[7:0]),
    .wr_en(dmem_wr_en & sel_uart), .rd_en(dmem_rd_en & sel_uart),
    .wdata(dmem_wdata), .rdata(uart_rdata),
    .uart_tx(uart_tx), .uart_rx(uart_rx), .irq(uart_irq)
  );

  timer u_timer (
    .clk(clk),        .rst_n(rst_n),
    .addr(dmem_addr[7:0]),
    .wr_en(dmem_wr_en & sel_timer), .rd_en(dmem_rd_en & sel_timer),
    .wdata(dmem_wdata), .rdata(timer_rdata), .irq(timer_irq)
  );
endmodule
