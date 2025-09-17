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

      @(negedge sclk);
      mosi = tx_data[43];
      cs_n = 0;

      for (i = 42; i >= 0; i = i - 1) begin
        @(negedge sclk);
        mosi = tx_data[i];
      end

      @(negedge sclk);
      mosi = 0;

      repeat(2) @(posedge sclk);

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

    // Test that addresses are properly masked to 10 bits
    // Send address with extra bits set (should be ignored)
    // Using address 0x7FF (bits set beyond 10-bit range)
    // This should be masked to 0x3FF

    // Write to "address" 0x7FF (should become 0x3FF)
    spi_transaction(2'b01, 10'h7FF, 32'hDEADBEEF, rx_data);
    // Check that echo shows masked address
    if (rx_data[41:32] !== 10'h3FF) begin
      $display("@@@FAIL");
      $finish;
    end

    // Write to actual 0x3FF for comparison
    spi_transaction(2'b01, 10'h3FF, 32'hCAFEBABE, rx_data);

    // Read from 0x3FF - should get the second write
    spi_transaction(2'b00, 10'h3FF, 32'h00000000, rx_data);
    if (rx_data[31:0] !== 32'hCAFEBABE) begin
      $display("@@@FAIL");
      $finish;
    end

    // Test address wraparound
    // Write to address 0x400 (bit 10 set) - should wrap to 0x000
    spi_transaction(2'b01, 10'h400, 32'h12345678, rx_data);
    if (rx_data[41:32] !== 10'h000) begin
      $display("@@@FAIL");
      $finish;
    end

    // Read from 0x000 to verify wraparound
    spi_transaction(2'b00, 10'h000, 32'h00000000, rx_data);
    if (rx_data[31:0] !== 32'h12345678) begin
      $display("@@@FAIL");
      $finish;
    end

    $display("@@@PASS");
    $finish;
  end

endmodule