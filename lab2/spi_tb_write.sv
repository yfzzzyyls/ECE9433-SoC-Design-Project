module spi_tb (
  output logic        sclk,
  output logic        r_en,
  output logic        w_en,
  output logic [9:0]  addr,
  output logic [31:0] data_o,
  input  logic [31:0] data_i
);

  logic cs_n;
  logic mosi;
  logic miso;
  logic [43:0] tx_data;
  logic [43:0] rx_data;
  integer i;

  spi_sub dut (
    .sclk(sclk),
    .cs_n(cs_n),
    .mosi(mosi),
    .miso(miso),
    .r_en(r_en),
    .w_en(w_en),
    .addr(addr),
    .data_o(data_o),
    .data_i(data_i)
  );

  initial begin
    sclk = 0;
    forever #5 sclk = ~sclk;
  end

  task spi_transaction(
    input [1:0] op,
    input [9:0] address,
    input [31:0] data,
    output [43:0] response
  );
    begin
      tx_data = {op, address, data};

      // Put first bit on MOSI, then assert cs_n
      @(negedge sclk);
      mosi = tx_data[43];  // MSB first
      cs_n = 0;

      // Send remaining 43 bits
      for (i = 42; i >= 0; i = i - 1) begin
        @(negedge sclk);
        mosi = tx_data[i];
      end

      // Hold mosi low during response
      @(negedge sclk);
      mosi = 0;

      // Wait through memory pulse and TX start according to golden design timing
      repeat(2) @(posedge sclk);  // Memory pulse + one more

      // Receive 44 bits
      for (i = 43; i >= 0; i = i - 1) begin
        @(posedge sclk);
        rx_data[i] = miso;
      end

      response = rx_data;

      @(posedge sclk);
      cs_n = 1;
      repeat(2) @(posedge sclk);
    end
  endtask

  initial begin
    cs_n = 1;
    mosi = 0;

    repeat(5) @(posedge sclk);

    // Test write operations with different patterns
    spi_transaction(2'b01, 10'h100, 32'hDEADBEEF, rx_data);
    $display("Expected: %h", {2'b01, 10'h100, 32'hDEADBEEF});
    $display("Got:      %h", rx_data);
    if (rx_data !== {2'b01, 10'h100, 32'hDEADBEEF}) begin
      $display("@@@FAIL");
      $finish;
    end

    spi_transaction(2'b01, 10'h200, 32'h12345678, rx_data);
    if (rx_data !== {2'b01, 10'h200, 32'h12345678}) begin
      $display("@@@FAIL");
      $finish;
    end

    spi_transaction(2'b01, 10'h3FF, 32'hFFFFFFFF, rx_data);
    if (rx_data !== {2'b01, 10'h3FF, 32'hFFFFFFFF}) begin
      $display("@@@FAIL");
      $finish;
    end

    spi_transaction(2'b01, 10'h000, 32'h00000000, rx_data);
    if (rx_data !== {2'b01, 10'h000, 32'h00000000}) begin
      $display("@@@FAIL");
      $finish;
    end

    $display("@@@PASS");
    $finish;
  end

endmodule