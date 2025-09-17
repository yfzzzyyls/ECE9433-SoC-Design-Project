// Stress Test - Back-to-back frames, no idle, rapid operations
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

  // Task for single frame (no cs_n deassert)
  task send_frame_no_deassert(
    input [1:0] op,
    input [9:0] address,
    input [31:0] data,
    output [43:0] response
  );
    begin
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
    end
  endtask

  // Main test sequence
  initial begin
    cs_n = 1;
    mosi = 0;
    error_count = 0;

    repeat(5) @(posedge sclk);

    // ===== Test 1: Back-to-Back Frames (no idle, cs_n stays low) =====
    $display("\n=== Test 1: Back-to-Back Frames with cs_n=0 Throughout ===");

    cs_n = 0;  // Keep low for multiple frames

    // Frame 1: Write
    send_frame_no_deassert(2'b01, 10'h001, 32'h11111111, rx_data);
    if (rx_data !== {2'b01, 10'h001, 32'h11111111}) begin
      $display("ERROR: Frame 1 failed");
      error_count = error_count + 1;
    end

    // Immediately start Frame 2 (no idle cycles)
    @(posedge sclk);

    // Frame 2: Write
    send_frame_no_deassert(2'b01, 10'h002, 32'h22222222, rx_data);
    if (rx_data !== {2'b01, 10'h002, 32'h22222222}) begin
      $display("ERROR: Frame 2 failed");
      error_count = error_count + 1;
    end

    // Frame 3: Read
    @(posedge sclk);
    send_frame_no_deassert(2'b00, 10'h001, 32'h00000000, rx_data);
    if (rx_data[31:0] !== 32'h11111111) begin
      $display("ERROR: Frame 3 read incorrect");
      error_count = error_count + 1;
    end

    // Frame 4: Read
    @(posedge sclk);
    send_frame_no_deassert(2'b00, 10'h002, 32'h00000000, rx_data);
    if (rx_data[31:0] !== 32'h22222222) begin
      $display("ERROR: Frame 4 read incorrect");
      error_count = error_count + 1;
    end

    @(posedge sclk);
    cs_n = 1;  // Finally deassert

    if (error_count == 0) begin
      $display("PASS: 4 back-to-back frames completed successfully");
    end

    repeat(5) @(posedge sclk);

    // ===== Test 2: Rapid Write-Read Pairs =====
    $display("\n=== Test 2: Rapid Write-Read Pairs ===");

    for (j = 0; j < 10; j = j + 1) begin
      // Write unique data
      cs_n = 0;
      send_frame_no_deassert(2'b01, j[9:0], {16'hBEEF, j[15:0]}, rx_data);

      // Read back immediately
      @(posedge sclk);
      send_frame_no_deassert(2'b00, j[9:0], 32'h00000000, rx_data);

      if (rx_data[15:0] !== j[15:0]) begin
        $display("ERROR: Rapid test %0d failed", j);
        error_count = error_count + 1;
      end

      @(posedge sclk);
      cs_n = 1;
      @(posedge sclk);  // Minimal gap
    end

    if (error_count == 0) begin
      $display("PASS: 10 rapid write-read pairs completed");
    end

    // ===== Test 3: Maximum Speed Operations =====
    $display("\n=== Test 3: Maximum Speed Continuous Operations ===");

    cs_n = 0;

    // Blast 20 writes as fast as possible
    for (j = 0; j < 20; j = j + 1) begin
      if (j > 0) @(posedge sclk);  // One cycle between frames
      send_frame_no_deassert(2'b01, 10'h100 + j[9:0], j[31:0], rx_data);
    end

    // Now read them all back
    for (j = 0; j < 20; j = j + 1) begin
      @(posedge sclk);
      send_frame_no_deassert(2'b00, 10'h100 + j[9:0], 32'h00000000, rx_data);
      if (rx_data[31:0] !== j[31:0]) begin
        $display("ERROR: Max speed read %0d incorrect", j);
        error_count = error_count + 1;
      end
    end

    @(posedge sclk);
    cs_n = 1;

    if (error_count == 0) begin
      $display("PASS: 40 maximum speed operations completed");
    end

    repeat(5) @(posedge sclk);

    // ===== Test 4: Alternating Opcodes =====
    $display("\n=== Test 4: Alternating Read/Write Operations ===");

    // Pre-write some data
    cs_n = 0;
    send_frame_no_deassert(2'b01, 10'h050, 32'hAAAAAAAA, rx_data);
    @(posedge sclk);
    cs_n = 1;
    @(posedge sclk);

    cs_n = 0;

    // Alternate read/write/read/write
    for (j = 0; j < 8; j = j + 1) begin
      if (j > 0) @(posedge sclk);

      if (j % 2 == 0) begin
        // Read
        send_frame_no_deassert(2'b00, 10'h050, 32'h00000000, rx_data);
        if (rx_data[31:0] !== 32'hAAAAAAAA) begin
          $display("ERROR: Alternating read %0d failed", j);
          error_count = error_count + 1;
        end
      end else begin
        // Write (overwrite same location)
        send_frame_no_deassert(2'b01, 10'h050, 32'hAAAAAAAA, rx_data);
        if (rx_data !== {2'b01, 10'h050, 32'hAAAAAAAA}) begin
          $display("ERROR: Alternating write %0d failed", j);
          error_count = error_count + 1;
        end
      end
    end

    @(posedge sclk);
    cs_n = 1;

    if (error_count == 0) begin
      $display("PASS: Alternating operations completed");
    end

    repeat(5) @(posedge sclk);

    // ===== Test 5: Abort and Restart Stress =====
    $display("\n=== Test 5: Abort and Restart Stress ===");

    for (j = 0; j < 5; j = j + 1) begin
      // Start transaction
      cs_n = 0;

      // Send partial frame (different lengths)
      for (i = 43; i >= (43 - 5*j - 10); i = i - 1) begin
        @(negedge sclk);
        mosi = (i % 2);
      end

      // Abort
      @(negedge sclk);
      cs_n = 1;

      // Very short gap
      @(posedge sclk);

      // Complete transaction
      cs_n = 0;
      send_frame_no_deassert(2'b01, 10'h080 + j[9:0], {27'b0, j[4:0]}, rx_data);

      if (rx_data !== {2'b01, 10'h080 + j[9:0], 27'b0, j[4:0]}) begin
        $display("ERROR: Abort/restart %0d failed", j);
        error_count = error_count + 1;
      end

      @(posedge sclk);
      cs_n = 1;
      @(posedge sclk);
    end

    if (error_count == 0) begin
      $display("PASS: 5 abort/restart cycles completed");
    end

    // ===== Test 6: Pattern Stress =====
    $display("\n=== Test 6: Data Pattern Stress ===");

    cs_n = 0;

    // All zeros
    send_frame_no_deassert(2'b01, 10'h000, 32'h00000000, rx_data);
    @(posedge sclk);

    // All ones
    send_frame_no_deassert(2'b01, 10'h3FF, 32'hFFFFFFFF, rx_data);
    @(posedge sclk);

    // Alternating 0xAAAAAAAA
    send_frame_no_deassert(2'b01, 10'h155, 32'hAAAAAAAA, rx_data);
    @(posedge sclk);

    // Alternating 0x55555555
    send_frame_no_deassert(2'b01, 10'h2AA, 32'h55555555, rx_data);
    @(posedge sclk);

    // Walking ones
    for (j = 0; j < 32; j = j + 1) begin
      @(posedge sclk);
      send_frame_no_deassert(2'b01, 10'h200 + j[9:0], (32'b1 << j), rx_data);
    end

    @(posedge sclk);
    cs_n = 1;

    $display("PASS: Pattern stress test completed");

    repeat(5) @(posedge sclk);

    // ===== Final Report =====
    $display("\n=== Stress Test Summary ===");
    if (error_count == 0) begin
      $display("All stress tests passed!");
      $display("@@@PASS");
    end else begin
      $display("Stress tests failed with %0d errors", error_count);
      $display("@@@FAIL");
    end

    $finish;
  end

endmodule