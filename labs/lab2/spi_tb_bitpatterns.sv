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

    // Test walking 1s pattern - can expose shift register bugs
    spi_transaction(2'b01, 10'h010, 32'h00000001, rx_data);
    if (rx_data !== {2'b01, 10'h010, 32'h00000001}) begin
      $display("@@@FAIL");
      $finish;
    end

    spi_transaction(2'b01, 10'h011, 32'h00000002, rx_data);
    if (rx_data !== {2'b01, 10'h011, 32'h00000002}) begin
      $display("@@@FAIL");
      $finish;
    end

    spi_transaction(2'b01, 10'h012, 32'h00000004, rx_data);
    if (rx_data !== {2'b01, 10'h012, 32'h00000004}) begin
      $display("@@@FAIL");
      $finish;
    end

    spi_transaction(2'b01, 10'h013, 32'h80000000, rx_data);
    if (rx_data !== {2'b01, 10'h013, 32'h80000000}) begin
      $display("@@@FAIL");
      $finish;
    end

    // Test patterns that might expose off-by-one bit shifts
    spi_transaction(2'b01, 10'h020, 32'h7FFFFFFF, rx_data);
    if (rx_data !== {2'b01, 10'h020, 32'h7FFFFFFF}) begin
      $display("@@@FAIL");
      $finish;
    end

    spi_transaction(2'b01, 10'h021, 32'hFFFFFFFE, rx_data);
    if (rx_data !== {2'b01, 10'h021, 32'hFFFFFFFE}) begin
      $display("@@@FAIL");
      $finish;
    end

    // Test specific problematic patterns
    spi_transaction(2'b01, 10'h030, 32'hA5A5A5A5, rx_data);
    if (rx_data !== {2'b01, 10'h030, 32'hA5A5A5A5}) begin
      $display("@@@FAIL");
      $finish;
    end

    spi_transaction(2'b01, 10'h031, 32'h5A5A5A5A, rx_data);
    if (rx_data !== {2'b01, 10'h031, 32'h5A5A5A5A}) begin
      $display("@@@FAIL");
      $finish;
    end

    // Verify reads work with these patterns
    spi_transaction(2'b00, 10'h010, 32'h00000000, rx_data);
    if (rx_data[31:0] !== 32'h00000001) begin
      $display("@@@FAIL");
      $finish;
    end

    spi_transaction(2'b00, 10'h013, 32'h00000000, rx_data);
    if (rx_data[31:0] !== 32'h80000000) begin
      $display("@@@FAIL");
      $finish;
    end

    $display("@@@PASS");
    $finish;
  end

endmodule