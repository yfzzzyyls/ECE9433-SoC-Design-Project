module spi_tb (
  output logic        sclk,
  output logic        r_en,
  output logic        w_en,
  output logic [9:0]  addr,
  output logic [31:0] data_o,
  input  logic [31:0] data_i
);

  // Internal SPI signals
  logic cs_n;
  logic mosi;
  logic miso;

  // Test variables
  logic [43:0] tx_data;
  logic [43:0] rx_data;
  integer i;
  integer error_count = 0;

  // Instantiate DUT
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

  // Clock generation
  logic clk_internal;
  initial begin
    clk_internal = 0;
    forever #5 clk_internal = ~clk_internal;
  end
  assign sclk = clk_internal;

  // Task to send 44 bits MSB first
  task send_spi_message(input [43:0] message);
    begin
      tx_data = message;
      cs_n = 0;

      for (i = 43; i >= 0; i = i - 1) begin
        @(negedge sclk);
        mosi = tx_data[i];
      end

      @(negedge sclk);
      mosi = 0;
    end
  endtask

  // Task to receive 44 bits MSB first
  task receive_spi_response(output [43:0] response);
    begin
      rx_data = 44'b0;

      @(posedge sclk);  // Memory access
      @(negedge sclk);  // TX starts

      for (i = 43; i >= 0; i = i - 1) begin
        @(posedge sclk);
        rx_data[i] = miso;
      end

      response = rx_data;
    end
  endtask

  // Task for complete SPI transaction
  task spi_transaction(
    input [1:0] op,
    input [9:0] address,
    input [31:0] data,
    output [43:0] response
  );
    begin
      send_spi_message({op, address, data});
      receive_spi_response(response);

      @(posedge sclk);
      cs_n = 1;

      repeat(2) @(posedge sclk);
    end
  endtask

  // Main test sequence - Edge cases
  initial begin
    cs_n = 1;
    mosi = 0;

    repeat(5) @(posedge sclk);

    // Test 1: All zeros data
    $display("\n=== Test 1: Write all zeros ===");
    spi_transaction(2'b01, 10'h000, 32'h00000000, rx_data);
    if (rx_data !== {2'b01, 10'h000, 32'h00000000}) begin
      $display("ERROR: All zeros write echo failed");
      error_count = error_count + 1;
    end

    // Test 2: All ones data
    $display("\n=== Test 2: Write all ones ===");
    spi_transaction(2'b01, 10'h3FF, 32'hFFFFFFFF, rx_data);
    if (rx_data !== {2'b01, 10'h3FF, 32'hFFFFFFFF}) begin
      $display("ERROR: All ones write echo failed");
      error_count = error_count + 1;
    end

    // Test 3: Alternating pattern
    $display("\n=== Test 3: Write alternating pattern ===");
    spi_transaction(2'b01, 10'h155, 32'hAAAAAAAA, rx_data);
    if (rx_data !== {2'b01, 10'h155, 32'hAAAAAAAA}) begin
      $display("ERROR: Alternating pattern write failed");
      error_count = error_count + 1;
    end

    // Test 4: Read back alternating pattern
    $display("\n=== Test 4: Read alternating pattern ===");
    spi_transaction(2'b00, 10'h155, 32'h00000000, rx_data);
    if (rx_data[31:0] !== 32'hAAAAAAAA) begin
      $display("ERROR: Alternating pattern read failed");
      error_count = error_count + 1;
    end

    // Test 5: Address boundary (max valid address for 8-bit RAM)
    $display("\n=== Test 5: Max address test ===");
    spi_transaction(2'b01, 10'h0FF, 32'h87654321, rx_data);
    if (rx_data !== {2'b01, 10'h0FF, 32'h87654321}) begin
      $display("ERROR: Max address write failed");
      error_count = error_count + 1;
    end

    // Test 6: Back-to-back transactions
    $display("\n=== Test 6: Back-to-back writes ===");
    spi_transaction(2'b01, 10'h001, 32'h11111111, rx_data);
    // Minimal gap - only 2 cycles
    spi_transaction(2'b01, 10'h002, 32'h22222222, rx_data);
    if (rx_data !== {2'b01, 10'h002, 32'h22222222}) begin
      $display("ERROR: Back-to-back transaction failed");
      error_count = error_count + 1;
    end

    // Final result
    if (error_count == 0) begin
      $display("\nAll edge case tests passed!");
      $display("@@@PASS");
    end else begin
      $display("\nEdge case tests failed with %0d errors", error_count);
      $display("@@@FAIL");
    end

    $finish;
  end

endmodule