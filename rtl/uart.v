// ============================================================================
// uart.sv — UART Peripheral 8N1 (Verilog-2001)
// Registers: 0x00 TX_DATA(WO), 0x04 RX_DATA(RO), 0x08 STATUS, 0x0C CTRL(div)
// ============================================================================
module uart (
  input         clk,
  input         rst_n,
  input  [7:0]  addr,
  input         wr_en,
  input         rd_en,
  input  [31:0] wdata,
  output reg [31:0] rdata,
  output reg    uart_tx,
  input         uart_rx,
  output        irq
);
  // TX FSM states
  parameter TX_IDLE  = 2'd0, TX_START = 2'd1,
            TX_DATA  = 2'd2, TX_STOP  = 2'd3;
  // RX FSM states
  parameter RX_IDLE  = 2'd0, RX_START = 2'd1,
            RX_DATA  = 2'd2, RX_STOP  = 2'd3;

  reg [15:0] clk_div;
  reg [1:0]  tx_state;
  reg [7:0]  tx_shift;
  reg [2:0]  tx_bit_cnt;
  reg [15:0] tx_clk_cnt;
  reg        tx_busy;
  reg [1:0]  rx_state;
  reg [7:0]  rx_shift, rx_data;
  reg [2:0]  rx_bit_cnt;
  reg [15:0] rx_clk_cnt;
  reg        rx_valid, rx_overrun;
  reg        rx_meta, rx_sync;

  // Double-sync RX
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin rx_meta <= 1'b1; rx_sync <= 1'b1; end
    else        begin rx_meta <= uart_rx; rx_sync <= rx_meta; end
  end

  // TX FSM
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tx_state <= TX_IDLE; uart_tx <= 1'b1;
      tx_busy <= 1'b0; tx_shift <= 8'b0;
      tx_bit_cnt <= 3'b0; tx_clk_cnt <= 16'b0;
    end else begin
      case (tx_state)
        TX_IDLE: begin
          uart_tx <= 1'b1;
          if (wr_en && addr[3:2] == 2'd0) begin
            tx_shift <= wdata[7:0]; tx_busy <= 1'b1;
            tx_state <= TX_START;   tx_clk_cnt <= clk_div;
          end
        end
        TX_START: begin
          uart_tx <= 1'b0;
          if (tx_clk_cnt == 16'b0) begin
            tx_clk_cnt <= clk_div; tx_bit_cnt <= 3'd0; tx_state <= TX_DATA;
          end else tx_clk_cnt <= tx_clk_cnt - 1'b1;
        end
        TX_DATA: begin
          uart_tx <= tx_shift[0];
          if (tx_clk_cnt == 16'b0) begin
            tx_clk_cnt <= clk_div; tx_shift <= {1'b0, tx_shift[7:1]};
            if (tx_bit_cnt == 3'd7) tx_state <= TX_STOP;
            else tx_bit_cnt <= tx_bit_cnt + 1'b1;
          end else tx_clk_cnt <= tx_clk_cnt - 1'b1;
        end
        TX_STOP: begin
          uart_tx <= 1'b1;
          if (tx_clk_cnt == 16'b0) begin tx_busy <= 1'b0; tx_state <= TX_IDLE; end
          else tx_clk_cnt <= tx_clk_cnt - 1'b1;
        end
      endcase
    end
  end

  // RX FSM
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rx_state <= RX_IDLE; rx_valid <= 1'b0; rx_overrun <= 1'b0;
      rx_data <= 8'b0; rx_shift <= 8'b0;
      rx_bit_cnt <= 3'b0; rx_clk_cnt <= 16'b0;
    end else begin
      if (rd_en && addr[3:2] == 2'd1) rx_valid <= 1'b0;
      case (rx_state)
        RX_IDLE: begin
          if (!rx_sync) begin
            rx_clk_cnt <= {1'b0, clk_div[15:1]}; rx_state <= RX_START;
          end
        end
        RX_START: begin
          if (rx_clk_cnt == 16'b0) begin
            if (!rx_sync) begin
              rx_clk_cnt <= clk_div; rx_bit_cnt <= 3'd0; rx_state <= RX_DATA;
            end else rx_state <= RX_IDLE;
          end else rx_clk_cnt <= rx_clk_cnt - 1'b1;
        end
        RX_DATA: begin
          if (rx_clk_cnt == 16'b0) begin
            rx_clk_cnt <= clk_div; rx_shift <= {rx_sync, rx_shift[7:1]};
            if (rx_bit_cnt == 3'd7) rx_state <= RX_STOP;
            else rx_bit_cnt <= rx_bit_cnt + 1'b1;
          end else rx_clk_cnt <= rx_clk_cnt - 1'b1;
        end
        RX_STOP: begin
          if (rx_clk_cnt == 16'b0) begin
            if (rx_sync) begin
              if (rx_valid) rx_overrun <= 1'b1;
              rx_data <= rx_shift; rx_valid <= 1'b1;
            end
            rx_state <= RX_IDLE;
          end else rx_clk_cnt <= rx_clk_cnt - 1'b1;
        end
      endcase
    end
  end

  // CTRL write
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) clk_div <= 16'd867;
    else if (wr_en && addr[3:2] == 2'd3) clk_div <= wdata[15:0];
  end

  // Register read
  always @(*) begin
    rdata = 32'b0;
    if (rd_en) begin
      case (addr[3:2])
        2'd0: rdata = 32'b0;
        2'd1: rdata = {24'b0, rx_data};
        2'd2: rdata = {29'b0, rx_overrun, rx_valid, tx_busy};
        2'd3: rdata = {16'b0, clk_div};
      endcase
    end
  end

  assign irq = rx_valid;
endmodule
