// ============================================================================
// gpio.sv — General-Purpose I/O Peripheral (Verilog-2001)
// Registers: 0x00 DATA_OUT, 0x04 DATA_IN, 0x08 DIR, 0x0C IRQ_EN, 0x10 IRQ_STAT
// ============================================================================
module gpio #(
  parameter WIDTH = 32
)(
  input              clk,
  input              rst_n,
  input  [7:0]       addr,
  input              wr_en,
  input              rd_en,
  input  [31:0]      wdata,
  output reg [31:0]  rdata,
  input  [WIDTH-1:0] gpio_in,
  output [WIDTH-1:0] gpio_out,
  output             irq
);
  reg [WIDTH-1:0] data_out, dir, irq_en, irq_stat;
  reg [WIDTH-1:0] gpio_in_meta, gpio_in_sync, gpio_in_prev;
  wire [WIDTH-1:0] rising_edge_det = gpio_in_sync & ~gpio_in_prev;

  // Double synchroniser
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      gpio_in_meta <= {WIDTH{1'b0}};
      gpio_in_sync <= {WIDTH{1'b0}};
      gpio_in_prev <= {WIDTH{1'b0}};
    end else begin
      gpio_in_meta <= gpio_in;
      gpio_in_sync <= gpio_in_meta;
      gpio_in_prev <= gpio_in_sync;
    end
  end

  // Register write
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      data_out <= {WIDTH{1'b0}};
      dir      <= {WIDTH{1'b0}};
      irq_en   <= {WIDTH{1'b0}};
      irq_stat <= {WIDTH{1'b0}};
    end else begin
      irq_stat <= irq_stat | (rising_edge_det & irq_en);
      if (wr_en) begin
        case (addr[4:2])
          3'd0: data_out <= wdata[WIDTH-1:0];
          3'd2: dir      <= wdata[WIDTH-1:0];
          3'd3: irq_en   <= wdata[WIDTH-1:0];
          3'd4: irq_stat <= irq_stat & ~wdata[WIDTH-1:0];
          default: ;
        endcase
      end
    end
  end

  // Register read
  always @(*) begin
    rdata = 32'b0;
    if (rd_en) begin
      case (addr[4:2])
        3'd0: rdata = {{(32-WIDTH){1'b0}}, data_out};
        3'd1: rdata = {{(32-WIDTH){1'b0}}, gpio_in_sync};
        3'd2: rdata = {{(32-WIDTH){1'b0}}, dir};
        3'd3: rdata = {{(32-WIDTH){1'b0}}, irq_en};
        3'd4: rdata = {{(32-WIDTH){1'b0}}, irq_stat};
        default: rdata = 32'b0;
      endcase
    end
  end

  assign gpio_out = data_out & dir;
  assign irq      = |(irq_stat & irq_en);
endmodule
