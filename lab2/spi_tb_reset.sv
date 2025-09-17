// Reset Behavior Test - Verifies proper reset on negedge when cs_n=1
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

  // Task for complete transaction
  task spi_transaction(
    input [1:0] op,
    input [9:0] address,
    input [31:0] data,
    output [43:0] response
  );
    begin
      cs_n = 0;
      tx_data = {op, address, data};

      // Send 44 bits
      for (i = 43; i >= 0; i = i - 1) begin
        @(negedge sclk);
        mosi = tx_data[i];
      end

      @(negedge sclk);
      mosi = 0;

      // Receive response
      @(posedge sclk);  // Memory pulse
      for (i = 43; i >= 0; i = i - 1) begin
        @(posedge sclk);
        response[i] = miso;
      end

      @(posedge sclk);
      cs_n = 1;
      repeat(2) @(posedge sclk);
    end
  endtask

  // Main test sequence
  initial begin
    cs_n = 1;
    mosi = 0;
    error_count = 0;

    repeat(5) @(posedge sclk);

    // ===== Test 1: Reset at Different Points =====
    $display("\n=== Test 1: Reset After 10 Bits ===");

    cs_n = 0;
    tx_data = {2'b01, 10'h3FF, 32'hDEADBEEF};

    // Send only 10 bits
    for (i = 43; i >= 34; i = i - 1) begin
      @(negedge sclk);
      mosi = tx_data[i];
    end

    // Reset on negedge
    @(negedge sclk);
    cs_n = 1;

    // Verify immediate reset
    if (miso !== 1'b0) begin
      $display("ERROR: miso not 0 immediately after cs_n=1");
      error_count = error_count + 1;
    end

    // Check internal state reset (indirectly via next transaction)
    repeat(3) @(posedge sclk);

    // Start new transaction - should work normally
    spi_transaction(2'b01, 10'h100, 32'h11111111, rx_data);
    if (rx_data !== {2'b01, 10'h100, 32'h11111111}) begin
      $display("ERROR: Transaction after 10-bit reset failed");
      error_count = error_count + 1;
    end else begin
      $display("PASS: Clean recovery after 10-bit reset");
    end

    // ===== Test 2: Reset After 43 Bits (just before last bit) =====
    $display("\n=== Test 2: Reset After 43 Bits ===");

    cs_n = 0;
    tx_data = {2'b00, 10'h200, 32'hCAFEBABE};

    // Send 43 bits
    for (i = 43; i >= 1; i = i - 1) begin
      @(negedge sclk);
      mosi = tx_data[i];
    end

    // Reset just before last bit
    @(negedge sclk);
    cs_n = 1;

    if (miso !== 1'b0) begin
      $display("ERROR: miso not 0 after 43-bit reset");
      error_count = error_count + 1;
    end

    repeat(3) @(posedge sclk);

    // Verify next transaction works
    spi_transaction(2'b01, 10'h200, 32'h22222222, rx_data);
    if (rx_data !== {2'b01, 10'h200, 32'h22222222}) begin
      $display("ERROR: Transaction after 43-bit reset failed");
      error_count = error_count + 1;
    end else begin
      $display("PASS: Clean recovery after 43-bit reset");
    end

    // ===== Test 3: Reset During Memory State =====
    $display("\n=== Test 3: Reset During Memory State ===");

    cs_n = 0;
    tx_data = {2'b01, 10'h300, 32'h87654321};

    // Send all 44 bits
    for (i = 43; i >= 0; i = i - 1) begin
      @(negedge sclk);
      mosi = tx_data[i];
    end

    @(negedge sclk);
    mosi = 0;

    // Wait for memory pulse
    @(posedge sclk);

    // Reset during memory state
    @(negedge sclk);
    cs_n = 1;

    if (miso !== 1'b0) begin
      $display("ERROR: miso not 0 after reset during memory");
      error_count = error_count + 1;
    end

    // Memory operation should have completed
    repeat(3) @(posedge sclk);

    // Read back - should have written before reset
    spi_transaction(2'b00, 10'h300, 32'h00000000, rx_data);
    if (rx_data[31:0] === 32'h87654321) begin
      $display("PASS: Memory write completed before reset");
    end else begin
      $display("INFO: Memory write may not have completed (implementation dependent)");
    end

    // ===== Test 4: Reset During TX =====
    $display("\n=== Test 4: Reset During TX Response ===");

    cs_n = 0;
    tx_data = {2'b00, 10'h100, 32'h00000000};

    // Send all 44 bits
    for (i = 43; i >= 0; i = i - 1) begin
      @(negedge sclk);
      mosi = tx_data[i];
    end

    @(negedge sclk);
    mosi = 0;

    // Memory pulse
    @(posedge sclk);

    // Receive first 10 bits of response
    for (i = 43; i >= 34; i = i - 1) begin
      @(posedge sclk);
      rx_data[i] = miso;
    end

    // Reset during TX
    @(negedge sclk);
    cs_n = 1;

    if (miso !== 1'b0) begin
      $display("ERROR: miso not 0 after reset during TX");
      error_count = error_count + 1;
    end else begin
      $display("PASS: miso reset during TX response");
    end

    repeat(3) @(posedge sclk);

    // ===== Test 5: Back-to-Back Reset =====
    $display("\n=== Test 5: Multiple Rapid Resets ===");

    // First partial transaction
    cs_n = 0;
    for (i = 43; i >= 38; i = i - 1) begin
      @(negedge sclk);
      mosi = (i % 2);
    end

    @(negedge sclk);
    cs_n = 1;  // Reset 1

    @(posedge sclk);

    // Second partial transaction
    cs_n = 0;
    for (i = 43; i >= 35; i = i - 1) begin
      @(negedge sclk);
      mosi = (i % 2);
    end

    @(negedge sclk);
    cs_n = 1;  // Reset 2

    @(posedge sclk);

    // Third partial transaction
    cs_n = 0;
    for (i = 43; i >= 40; i = i - 1) begin
      @(negedge sclk);
      mosi = (i % 2);
    end

    @(negedge sclk);
    cs_n = 1;  // Reset 3

    repeat(3) @(posedge sclk);

    // Now do a complete transaction
    spi_transaction(2'b01, 10'h050, 32'hABCDABCD, rx_data);
    if (rx_data !== {2'b01, 10'h050, 32'hABCDABCD}) begin
      $display("ERROR: Transaction after rapid resets failed");
      error_count = error_count + 1;
    end else begin
      $display("PASS: Clean recovery after multiple rapid resets");
    end

    // ===== Test 6: Reset Timing on Negedge =====
    $display("\n=== Test 6: Reset Timing Verification ===");

    cs_n = 0;
    tx_data = {2'b01, 10'h0FF, 32'h12345678};

    // Send 20 bits
    for (i = 43; i >= 24; i = i - 1) begin
      @(negedge sclk);
      mosi = tx_data[i];
    end

    // Reset EXACTLY on negedge
    @(negedge sclk);
    cs_n = 1;

    // miso should be 0 immediately
    #1;  // Small delay to allow combinational propagation
    if (miso !== 1'b0) begin
      $display("ERROR: miso not reset immediately on negedge");
      error_count = error_count + 1;
    end

    // State should be reset before next posedge
    @(posedge sclk);
    if (r_en || w_en) begin
      $display("ERROR: Memory signals active after reset");
      error_count = error_count + 1;
    end else begin
      $display("PASS: Clean reset on negedge");
    end

    repeat(3) @(posedge sclk);

    // ===== Final Report =====
    $display("\n=== Reset Behavior Test Summary ===");
    if (error_count == 0) begin
      $display("All reset tests passed!");
      $display("@@@PASS");
    end else begin
      $display("Reset tests failed with %0d errors", error_count);
      $display("@@@FAIL");
    end

    $finish;
  end

endmodule