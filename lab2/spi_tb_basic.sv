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
    forever #5 sclk = ~sclk;
  end

  // Basic SPI transaction - no timing assumptions
  task spi_transaction(
    input [1:0] op,
    input [9:0] address,
    input [31:0] data,
    output [43:0] response
  );
    begin
      // Start transaction
      @(negedge sclk);
      cs_n = 0;

      // Send 44 bits MSB first
      tx_data = {op, address, data};
      for (i = 43; i >= 0; i = i - 1) begin
        @(negedge sclk);
        mosi = tx_data[i];
      end

      // Hold mosi low during response
      @(negedge sclk);
      mosi = 0;

      // Skip one cycle for memory access
      @(posedge sclk);

      // Receive 44 bits
      for (i = 43; i >= 0; i = i - 1) begin
        @(posedge sclk);
        rx_data[i] = miso;
      end

      response = rx_data;

      // End transaction
      @(posedge sclk);
      cs_n = 1;
      repeat(2) @(posedge sclk);
    end
  endtask

  // Main test - only test the most basic requirements
  initial begin
    cs_n = 1;
    mosi = 0;

    // Wait for reset
    repeat(5) @(posedge sclk);

    // Test 1: Basic write operation - echo check
    // The spec says write should echo the message
    spi_transaction(2'b01, 10'h100, 32'h9A364721, rx_data);
    if (rx_data !== {2'b01, 10'h100, 32'h9A364721}) begin
      $display("@@@FAIL");
      $finish;
    end

    // Test 2: Basic read operation - just check format
    // We can't assume what data will be read from uninitialized memory
    // So just check that opcode and address are echoed correctly
    spi_transaction(2'b00, 10'h100, 32'h00000000, rx_data);
    if (rx_data[43:32] !== {2'b00, 10'h100}) begin
      $display("@@@FAIL");
      $finish;
    end
    // Data should be what we wrote before
    if (rx_data[31:0] !== 32'h9A364721) begin
      $display("@@@FAIL");
      $finish;
    end

    $display("@@@PASS");
    $finish;
  end

endmodule