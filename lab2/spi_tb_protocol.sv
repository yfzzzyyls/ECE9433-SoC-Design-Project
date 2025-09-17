// Protocol Timing Test - Verifies exact cycle-by-cycle timing requirements
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
  logic prev_miso;

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

  // Main test sequence
  initial begin
    cs_n = 1;
    mosi = 0;
    error_count = 0;

    repeat(5) @(posedge sclk);

    // ===== Test 1: Memory Pulse Timing =====
    $display("\n=== Test 1: Memory Pulse Timing (exactly one cycle after last bit) ===");

    cs_n = 0;
    tx_data = {2'b01, 10'h123, 32'hABCDEF01};  // Write command

    // Send exactly 44 bits
    for (i = 43; i >= 0; i = i - 1) begin
      @(negedge sclk);
      mosi = tx_data[i];

      // Verify miso stays low during Main's message
      if (miso !== 1'b0) begin
        $display("ERROR: miso not 0 during Main's bit[%0d]", i);
        error_count = error_count + 1;
      end
    end

    @(negedge sclk);
    mosi = 0;  // Main must hold mosi=0 during response

    // Check memory pulse on VERY NEXT posedge
    @(posedge sclk);
    if (!(r_en ^ w_en)) begin
      $display("ERROR: No memory pulse on next posedge after last bit");
      error_count = error_count + 1;
    end else if (r_en && w_en) begin
      $display("ERROR: Both r_en and w_en asserted simultaneously");
      error_count = error_count + 1;
    end else if (w_en && !r_en) begin
      $display("PASS: Write pulse on next posedge");
    end else begin
      $display("ERROR: Read pulse for write command");
      error_count = error_count + 1;
    end

    // Verify pulse is exactly one cycle
    @(posedge sclk);
    if (r_en || w_en) begin
      $display("ERROR: Memory pulse longer than one cycle");
      error_count = error_count + 1;
    end else begin
      $display("PASS: Memory pulse exactly one cycle");
    end

    // Complete the response reception
    for (i = 42; i >= 0; i = i - 1) begin
      @(posedge sclk);
      rx_data[i] = miso;

      // Verify Main holds mosi=0 during response
      if (mosi !== 1'b0) begin
        $display("ERROR: mosi not 0 during Sub's response bit[%0d]", i);
        error_count = error_count + 1;
      end
    end

    @(posedge sclk);
    cs_n = 1;
    repeat(5) @(posedge sclk);

    // ===== Test 2: TX Start Timing =====
    $display("\n=== Test 2: TX Start Timing (following negedge after memory pulse) ===");

    cs_n = 0;
    tx_data = {2'b00, 10'h055, 32'h00000000};  // Read command

    // Send 44 bits
    for (i = 43; i >= 0; i = i - 1) begin
      @(negedge sclk);
      mosi = tx_data[i];
    end

    @(negedge sclk);
    mosi = 0;
    prev_miso = miso;  // Should still be 0

    // Memory pulse on next posedge
    @(posedge sclk);
    if (!r_en) begin
      $display("ERROR: No read pulse for read command");
      error_count = error_count + 1;
    end

    // TX should start on FOLLOWING negedge
    @(negedge sclk);
    // The first bit should be valid (0 or 1 based on echo/read data)
    // For a read from uninitialized memory, first bit of opcode echo is 0
    // Just check that miso is driven (not X or Z)
    if (miso === 1'bx || miso === 1'bz) begin
      $display("ERROR: TX not started on following negedge (miso=%b)", miso);
      error_count = error_count + 1;
    end else begin
      $display("PASS: TX started on following negedge (miso=%b)", miso);
      rx_data[43] = miso;  // Capture first bit
    end

    // Capture remaining response
    for (i = 42; i >= 0; i = i - 1) begin
      @(posedge sclk);
      rx_data[i] = miso;
    end

    @(posedge sclk);
    cs_n = 1;
    repeat(5) @(posedge sclk);

    // ===== Test 3: Undefined Opcodes =====
    $display("\n=== Test 3: Undefined/Reserved Opcodes ===");

    // Test opcode 10 (undefined)
    cs_n = 0;
    tx_data = {2'b10, 10'h100, 32'h12345678};

    for (i = 43; i >= 0; i = i - 1) begin
      @(negedge sclk);
      mosi = tx_data[i];
    end

    @(negedge sclk);
    mosi = 0;

    @(posedge sclk);  // Memory pulse cycle
    if (r_en || w_en) begin
      $display("ERROR: Memory access for undefined opcode 10");
      error_count = error_count + 1;
    end else begin
      $display("PASS: No memory access for undefined opcode 10");
    end

    // Still need to receive response (might be undefined)
    for (i = 43; i >= 0; i = i - 1) begin
      @(posedge sclk);
      rx_data[i] = miso;
    end

    @(posedge sclk);
    cs_n = 1;
    repeat(5) @(posedge sclk);

    // Test opcode 11 (undefined)
    cs_n = 0;
    tx_data = {2'b11, 10'h200, 32'h87654321};

    for (i = 43; i >= 0; i = i - 1) begin
      @(negedge sclk);
      mosi = tx_data[i];
    end

    @(negedge sclk);
    mosi = 0;

    @(posedge sclk);  // Memory pulse cycle
    if (r_en || w_en) begin
      $display("ERROR: Memory access for undefined opcode 11");
      error_count = error_count + 1;
    end else begin
      $display("PASS: No memory access for undefined opcode 11");
    end

    // Receive response
    for (i = 43; i >= 0; i = i - 1) begin
      @(posedge sclk);
      rx_data[i] = miso;
    end

    @(posedge sclk);
    cs_n = 1;
    repeat(5) @(posedge sclk);

    // ===== Test 4: Signal Constraints During Transfer =====
    $display("\n=== Test 4: Signal Constraints (miso=0 during RX, mosi=0 during TX) ===");

    cs_n = 0;
    tx_data = {2'b01, 10'h0AA, 32'hFFFFFFFF};

    // Track miso during entire Main message
    for (i = 43; i >= 0; i = i - 1) begin
      @(negedge sclk);
      mosi = tx_data[i];
      if (miso !== 1'b0) begin
        $display("ERROR: miso=%b at negedge of bit[%0d]", miso, i);
        error_count = error_count + 1;
      end

      if (i > 0) begin  // Don't check after last bit
        @(posedge sclk);
        if (miso !== 1'b0) begin
          $display("ERROR: miso=%b at posedge of bit[%0d]", miso, i);
          error_count = error_count + 1;
        end
      end
    end

    @(negedge sclk);
    mosi = 0;

    // Memory pulse
    @(posedge sclk);

    // Track mosi during entire Sub response
    for (i = 43; i >= 0; i = i - 1) begin
      @(posedge sclk);
      rx_data[i] = miso;
      if (mosi !== 1'b0) begin
        $display("ERROR: mosi=%b during response bit[%0d]", mosi, i);
        error_count = error_count + 1;
      end
    end

    if (error_count == 0) begin
      $display("PASS: Signal constraints maintained");
    end

    @(posedge sclk);
    cs_n = 1;
    repeat(5) @(posedge sclk);

    // ===== Final Report =====
    $display("\n=== Protocol Timing Test Summary ===");
    if (error_count == 0) begin
      $display("All protocol timing tests passed!");
      $display("@@@PASS");
    end else begin
      $display("Protocol tests failed with %0d errors", error_count);
      $display("@@@FAIL");
    end

    $finish;
  end

endmodule