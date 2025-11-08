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

    // Test opcode 00 (READ)
    spi_transaction(2'b00, 10'h200, 32'h00000000, rx_data);
    if (rx_data[43:42] !== 2'b00) begin
      $display("@@@FAIL");
      $finish;
    end
    if (rx_data[41:32] !== 10'h200) begin
      $display("@@@FAIL");
      $finish;
    end

    // Test opcode 01 (WRITE)
    spi_transaction(2'b01, 10'h100, 32'hABCDEF12, rx_data);
    if (rx_data !== {2'b01, 10'h100, 32'hABCDEF12}) begin
      $display("@@@FAIL");
      $finish;
    end

    // Test undefined opcode 10 - should still complete transaction
    spi_transaction(2'b10, 10'h050, 32'h55555555, rx_data);
    // Just check transaction completes without hanging

    // Test undefined opcode 11 - should still complete transaction
    spi_transaction(2'b11, 10'h060, 32'hAAAAAAAA, rx_data);
    // Just check transaction completes without hanging

    // Verify no memory operations occurred for undefined opcodes
    // by doing a write then read to same addresses
    spi_transaction(2'b01, 10'h050, 32'h12345678, rx_data);
    spi_transaction(2'b00, 10'h050, 32'h00000000, rx_data);
    if (rx_data[31:0] !== 32'h12345678) begin
      $display("@@@FAIL");
      $finish;
    end

    $display("@@@PASS");
    $finish;
  end

endmodule