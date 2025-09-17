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
  integer i, j;
  integer error_count = 0;
  integer timeout_count;

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

      // Send 44 bits MSB first
      for (i = 43; i >= 0; i = i - 1) begin
        @(negedge sclk);
        mosi = tx_data[i];
      end

      // Hold mosi low during response
      @(negedge sclk);
      mosi = 0;
    end
  endtask

  // Flexible receive task that waits for first bit to appear
  task receive_spi_response_flexible(output [43:0] response);
    begin
      rx_data = 44'b0;
      timeout_count = 0;

      // Wait for memory operation to complete (max 3 cycles)
      // Different implementations might have slightly different timing
      while (timeout_count < 6) begin
        @(negedge sclk);
        if (miso !== 1'b0 && miso !== 1'bz) begin
          // Found first bit!
          rx_data[43] = miso;
          break;
        end
        @(posedge sclk);
        if (miso !== 1'b0 && miso !== 1'bz) begin
          // Found first bit on posedge sample
          rx_data[43] = miso;
          break;
        end
        timeout_count = timeout_count + 1;
      end

      if (timeout_count >= 6) begin
        $display("ERROR: Timeout waiting for response");
        error_count = error_count + 1;
        response = 44'hx;
        return;
      end

      // Receive remaining 43 bits
      for (i = 42; i >= 0; i = i - 1) begin
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
      receive_spi_response_flexible(response);

      @(posedge sclk);
      cs_n = 1;

      repeat(2) @(posedge sclk);
    end
  endtask

  // Main test sequence
  initial begin
    cs_n = 1;
    mosi = 0;

    repeat(5) @(posedge sclk);

    // Test 1: Basic write
    $display("\n=== Test 1: Write to address 0x010 ===");
    spi_transaction(2'b01, 10'h010, 32'hDEADBEEF, rx_data);

    if (rx_data[43:42] !== 2'b01 || rx_data[41:32] !== 10'h010 || rx_data[31:0] !== 32'hDEADBEEF) begin
      $display("ERROR: Write echo incorrect");
      $display("  Expected: %h", {2'b01, 10'h010, 32'hDEADBEEF});
      $display("  Got:      %h", rx_data);
      error_count = error_count + 1;
    end

    // Test 2: Read back
    $display("\n=== Test 2: Read from address 0x010 ===");
    spi_transaction(2'b00, 10'h010, 32'h00000000, rx_data);

    if (rx_data[43:42] !== 2'b00 || rx_data[41:32] !== 10'h010) begin
      $display("ERROR: Read header incorrect");
      error_count = error_count + 1;
    end else if (rx_data[31:0] !== 32'hDEADBEEF) begin
      $display("ERROR: Read data mismatch");
      $display("  Expected: %h", 32'hDEADBEEF);
      $display("  Got:      %h", rx_data[31:0]);
      error_count = error_count + 1;
    end

    // Test 3: Multiple writes and reads
    $display("\n=== Test 3: Multiple operations ===");

    // Write different values to different addresses
    spi_transaction(2'b01, 10'h020, 32'h12345678, rx_data);
    if (rx_data !== {2'b01, 10'h020, 32'h12345678}) begin
      error_count = error_count + 1;
    end

    spi_transaction(2'b01, 10'h030, 32'hAAAA5555, rx_data);
    if (rx_data !== {2'b01, 10'h030, 32'hAAAA5555}) begin
      error_count = error_count + 1;
    end

    // Read them back
    spi_transaction(2'b00, 10'h020, 32'h00000000, rx_data);
    if (rx_data[31:0] !== 32'h12345678) begin
      $display("ERROR: Data at 0x020 incorrect");
      error_count = error_count + 1;
    end

    spi_transaction(2'b00, 10'h030, 32'h00000000, rx_data);
    if (rx_data[31:0] !== 32'hAAAA5555) begin
      $display("ERROR: Data at 0x030 incorrect");
      error_count = error_count + 1;
    end

    // Verify first address still intact
    spi_transaction(2'b00, 10'h010, 32'h00000000, rx_data);
    if (rx_data[31:0] !== 32'hDEADBEEF) begin
      $display("ERROR: Data at 0x010 corrupted");
      error_count = error_count + 1;
    end

    // Final result
    if (error_count == 0) begin
      $display("\n=== All tests passed! ===");
      $display("@@@PASS");
    end else begin
      $display("\n=== Tests failed with %0d errors ===", error_count);
      $display("@@@FAIL");
    end

    $finish;
  end

endmodule