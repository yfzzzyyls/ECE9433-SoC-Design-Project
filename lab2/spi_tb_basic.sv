`timescale 1ns/1ps

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
  initial begin
    sclk = 0;
    forever #5 sclk = ~sclk;  // 100 MHz clock
  end

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

      // Wait for memory access cycle
      @(posedge sclk);

      // Receive 44 bits MSB first
      // Sub drives on negedge, main samples on posedge
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

  // Debug monitoring
  always @(posedge sclk) begin
    if (w_en) begin
      $display("DEBUG: Write enable at time %0t, addr=%h, data=%h", $time, addr, data_o);
    end
    if (r_en) begin
      $display("DEBUG: Read enable at time %0t, addr=%h, data_i=%h", $time, addr, data_i);
    end
  end

  // Main test sequence
  initial begin
    // Initialize
    cs_n = 1;
    mosi = 0;

    // Wait for reset
    repeat(5) @(posedge sclk);

    // Test 1: Write operation
    $display("\n=== Test 1: Write 0xDEADBEEF to address 0x010 ===");
    spi_transaction(2'b01, 10'h010, 32'hDEADBEEF, rx_data);

    // Check write echo
    if (rx_data !== {2'b01, 10'h010, 32'hDEADBEEF}) begin
      $display("ERROR: Write echo mismatch");
      $display("  Expected: %h", {2'b01, 10'h010, 32'hDEADBEEF});
      $display("  Got:      %h", rx_data);
      error_count = error_count + 1;
    end else begin
      $display("PASS: Write echo correct");
    end

    // Test 2: Read operation
    $display("\n=== Test 2: Read from address 0x010 ===");
    spi_transaction(2'b00, 10'h010, 32'h00000000, rx_data);

    // Check read response
    if (rx_data[43:32] !== {2'b00, 10'h010}) begin
      $display("ERROR: Read header mismatch");
      $display("  Expected header: %h", {2'b00, 10'h010});
      $display("  Got header:      %h", rx_data[43:32]);
      error_count = error_count + 1;
    end else if (rx_data[31:0] !== 32'hDEADBEEF) begin
      $display("ERROR: Read data mismatch");
      $display("  Expected data: %h", 32'hDEADBEEF);
      $display("  Got data:      %h", rx_data[31:0]);
      error_count = error_count + 1;
    end else begin
      $display("PASS: Read data correct");
    end

    // Test 3: Write to different address
    $display("\n=== Test 3: Write 0x12345678 to address 0x020 ===");
    spi_transaction(2'b01, 10'h020, 32'h12345678, rx_data);

    if (rx_data !== {2'b01, 10'h020, 32'h12345678}) begin
      $display("ERROR: Write echo mismatch");
      $display("  Expected: %h", {2'b01, 10'h020, 32'h12345678});
      $display("  Got:      %h", rx_data);
      error_count = error_count + 1;
    end else begin
      $display("PASS: Write echo correct");
    end

    // Test 4: Read from new address
    $display("\n=== Test 4: Read from address 0x020 ===");
    spi_transaction(2'b00, 10'h020, 32'h00000000, rx_data);

    if (rx_data[31:0] !== 32'h12345678) begin
      $display("ERROR: Read data mismatch");
      $display("  Expected data: %h", 32'h12345678);
      $display("  Got data:      %h", rx_data[31:0]);
      error_count = error_count + 1;
    end else begin
      $display("PASS: Read data correct");
    end

    // Test 5: Verify first address still has data
    $display("\n=== Test 5: Verify address 0x010 still has 0xDEADBEEF ===");
    spi_transaction(2'b00, 10'h010, 32'h00000000, rx_data);

    if (rx_data[31:0] !== 32'hDEADBEEF) begin
      $display("ERROR: Data at address 0x010 corrupted");
      $display("  Expected data: %h", 32'hDEADBEEF);
      $display("  Got data:      %h", rx_data[31:0]);
      error_count = error_count + 1;
    end else begin
      $display("PASS: Data preserved correctly");
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