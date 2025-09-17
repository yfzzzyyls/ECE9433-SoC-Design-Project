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

  // Clock generation using assign statement for output port
  logic clk_internal;
  initial begin
    clk_internal = 0;
    forever #5 clk_internal = ~clk_internal;  // 100 MHz clock
  end
  assign sclk = clk_internal;

  // Task to send 44 bits MSB first
  task send_spi_message(input [43:0] message);
    begin
      tx_data = message;
      cs_n = 0;  // Assert chip select

      // Send 44 bits MSB first
      // Main drives on negedge, sub samples on posedge
      for (i = 43; i >= 0; i = i - 1) begin
        @(negedge sclk);
        mosi = tx_data[i];
      end

      // Hold mosi low during response
      @(negedge sclk);
      mosi = 0;
    end
  endtask

  // Task to receive 44 bits MSB first
  task receive_spi_response(output [43:0] response);
    begin
      rx_data = 44'b0;

      // Wait for at least one posedge for memory access
      @(posedge sclk);

      // Now we need to sample 44 bits
      // The sub drives on negedge, main samples on posedge
      // We should sample starting from the next posedge
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

      // Deassert chip select
      @(posedge sclk);
      cs_n = 1;

      // Wait a few cycles between transactions
      repeat(2) @(posedge sclk);
    end
  endtask


  // Main test sequence
  initial begin
    // Initialize
    cs_n = 1;
    mosi = 0;

    // Wait for reset
    repeat(5) @(posedge sclk);

    // Test 1: Write all ones (catches shift issues)
    $display("\n=== Test 1: Write 0xFFFFFFFF to address 0x3FF ===");
    spi_transaction(2'b01, 10'h3FF, 32'hFFFFFFFF, rx_data);
    if (rx_data !== {2'b01, 10'h3FF, 32'hFFFFFFFF}) begin
      $display("ERROR: All ones write echo mismatch");
      error_count = error_count + 1;
    end else begin
      $display("PASS: All ones write echo correct");
    end

    // Test 2: Read back all ones
    $display("\n=== Test 2: Read from address 0x3FF ===");
    spi_transaction(2'b00, 10'h3FF, 32'h00000000, rx_data);
    if (rx_data[31:0] !== 32'hFFFFFFFF) begin
      $display("ERROR: All ones read mismatch");
      error_count = error_count + 1;
    end else begin
      $display("PASS: All ones read correct");
    end

    // Test 3: Write pattern with MSB=1 (catches bit[31]=1 issues)
    $display("\n=== Test 3: Write 0x80000001 to address 0x001 ===");
    spi_transaction(2'b01, 10'h001, 32'h80000001, rx_data);
    if (rx_data !== {2'b01, 10'h001, 32'h80000001}) begin
      $display("ERROR: MSB pattern write echo mismatch");
      error_count = error_count + 1;
    end else begin
      $display("PASS: MSB pattern write echo correct");
    end

    // Test 4: Write alternating pattern (catches stuck bits)
    $display("\n=== Test 4: Write 0xAAAAAAAA to address 0x155 ===");
    spi_transaction(2'b01, 10'h155, 32'hAAAAAAAA, rx_data);
    if (rx_data !== {2'b01, 10'h155, 32'hAAAAAAAA}) begin
      $display("ERROR: Alternating pattern write mismatch");
      error_count = error_count + 1;
    end else begin
      $display("PASS: Alternating pattern write correct");
    end

    // Test 5: Write inverted alternating pattern
    $display("\n=== Test 5: Write 0x55555555 to address 0x2AA ===");
    spi_transaction(2'b01, 10'h2AA, 32'h55555555, rx_data);
    if (rx_data !== {2'b01, 10'h2AA, 32'h55555555}) begin
      $display("ERROR: Inverted pattern write mismatch");
      error_count = error_count + 1;
    end else begin
      $display("PASS: Inverted pattern write correct");
    end

    // Test 6: Write with single bit set (catches specific bit issues)
    $display("\n=== Test 6: Write 0x00000001 to address 0x100 ===");
    spi_transaction(2'b01, 10'h100, 32'h00000001, rx_data);
    if (rx_data !== {2'b01, 10'h100, 32'h00000001}) begin
      $display("ERROR: Single bit write mismatch");
      error_count = error_count + 1;
    end else begin
      $display("PASS: Single bit write correct");
    end

    // Test 7: Read back and verify all values
    $display("\n=== Test 7: Verify all stored values ===");

    spi_transaction(2'b00, 10'h001, 32'h00000000, rx_data);
    if (rx_data[31:0] !== 32'h80000001) begin
      $display("ERROR: Data at 0x001 corrupted");
      error_count = error_count + 1;
    end

    spi_transaction(2'b00, 10'h155, 32'h00000000, rx_data);
    if (rx_data[31:0] !== 32'hAAAAAAAA) begin
      $display("ERROR: Data at 0x155 corrupted");
      error_count = error_count + 1;
    end

    spi_transaction(2'b00, 10'h2AA, 32'h00000000, rx_data);
    if (rx_data[31:0] !== 32'h55555555) begin
      $display("ERROR: Data at 0x2AA corrupted");
      error_count = error_count + 1;
    end

    // Test 8: Write all zeros (important edge case)
    $display("\n=== Test 8: Write 0x00000000 to address 0x000 ===");
    spi_transaction(2'b01, 10'h000, 32'h00000000, rx_data);
    if (rx_data !== {2'b01, 10'h000, 32'h00000000}) begin
      $display("ERROR: All zeros write failed");
      error_count = error_count + 1;
    end else begin
      $display("PASS: All zeros write correct");
    end

    // Test 9: Read from unwritten address (should return 0)
    $display("\n=== Test 9: Read from unwritten address 0x0FF ===");
    spi_transaction(2'b00, 10'h0FF, 32'h00000000, rx_data);
    if (rx_data[43:32] !== {2'b00, 10'h0FF}) begin
      $display("ERROR: Read header incorrect for unwritten address");
      error_count = error_count + 1;
    end else begin
      $display("PASS: Read from unwritten address works");
    end

    // Test 10: Overwrite existing data
    $display("\n=== Test 10: Overwrite address 0x001 with 0x7FFFFFFF ===");
    spi_transaction(2'b01, 10'h001, 32'h7FFFFFFF, rx_data);
    if (rx_data !== {2'b01, 10'h001, 32'h7FFFFFFF}) begin
      $display("ERROR: Overwrite failed");
      error_count = error_count + 1;
    end else begin
      $display("PASS: Overwrite successful");
    end

    // Verify overwrite worked
    spi_transaction(2'b00, 10'h001, 32'h00000000, rx_data);
    if (rx_data[31:0] !== 32'h7FFFFFFF) begin
      $display("ERROR: Overwritten data not correct");
      error_count = error_count + 1;
    end

    // Test 11: Sequential addresses
    $display("\n=== Test 11: Sequential address writes ===");
    spi_transaction(2'b01, 10'h050, 32'h11111111, rx_data);
    if (rx_data !== {2'b01, 10'h050, 32'h11111111}) error_count = error_count + 1;

    spi_transaction(2'b01, 10'h051, 32'h22222222, rx_data);
    if (rx_data !== {2'b01, 10'h051, 32'h22222222}) error_count = error_count + 1;

    spi_transaction(2'b01, 10'h052, 32'h33333333, rx_data);
    if (rx_data !== {2'b01, 10'h052, 32'h33333333}) error_count = error_count + 1;

    spi_transaction(2'b01, 10'h053, 32'h44444444, rx_data);
    if (rx_data !== {2'b01, 10'h053, 32'h44444444}) error_count = error_count + 1;

    // Verify sequential reads
    spi_transaction(2'b00, 10'h050, 32'h00000000, rx_data);
    if (rx_data[31:0] !== 32'h11111111) error_count = error_count + 1;

    spi_transaction(2'b00, 10'h051, 32'h00000000, rx_data);
    if (rx_data[31:0] !== 32'h22222222) error_count = error_count + 1;

    spi_transaction(2'b00, 10'h052, 32'h00000000, rx_data);
    if (rx_data[31:0] !== 32'h33333333) error_count = error_count + 1;

    spi_transaction(2'b00, 10'h053, 32'h00000000, rx_data);
    if (rx_data[31:0] !== 32'h44444444) begin
      $display("ERROR: Sequential operations failed");
      error_count = error_count + 1;
    end else begin
      $display("PASS: Sequential operations work");
    end

    // Test 12: Back-to-back read-write-read
    $display("\n=== Test 12: Read-Write-Read sequence ===");
    spi_transaction(2'b00, 10'h155, 32'h00000000, rx_data);  // Read existing
    if (rx_data[31:0] !== 32'hAAAAAAAA) begin
      error_count = error_count + 1;
    end
    spi_transaction(2'b01, 10'h155, 32'hDEADBEEF, rx_data);  // Overwrite
    spi_transaction(2'b00, 10'h155, 32'h00000000, rx_data);  // Read new
    if (rx_data[31:0] !== 32'hDEADBEEF) begin
      $display("ERROR: Read-Write-Read sequence failed");
      error_count = error_count + 1;
    end else begin
      $display("PASS: Read-Write-Read sequence works");
    end

    // Report final results
    $display("\n=== Test Summary ===");
    if (error_count == 0) begin
      $display("All tests passed!");
      $display("@@@PASS");
    end else begin
      $display("Tests failed with %0d errors", error_count);
      $display("@@@FAIL");
    end

    $finish;
  end

endmodule