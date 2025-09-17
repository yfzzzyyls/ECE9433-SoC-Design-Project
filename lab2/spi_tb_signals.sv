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

  initial begin
    cs_n = 1;
    mosi = 0;

    repeat(5) @(posedge sclk);

    // Test that MISO stays low during Main's transmission
    tx_data = {2'b01, 10'h0F0, 32'hCAFEBABE};

    @(negedge sclk);
    mosi = tx_data[43];
    cs_n = 0;

    // During Main's transmission, MISO must be 0
    for (i = 42; i >= 0; i = i - 1) begin
      @(negedge sclk);
      mosi = tx_data[i];

      // Check MISO is 0 during RX
      if (miso !== 1'b0) begin
        $display("@@@FAIL");
        $finish;
      end
    end

    @(negedge sclk);
    mosi = 0;

    // Check r_en and w_en are never both high
    @(posedge sclk);
    if (r_en && w_en) begin
      $display("@@@FAIL");
      $finish;
    end

    // During response, collect data
    for (i = 43; i >= 0; i = i - 1) begin
      @(posedge sclk);
      rx_data[i] = miso;
    end

    @(posedge sclk);
    cs_n = 1;

    // Verify response
    if (rx_data !== {2'b01, 10'h0F0, 32'hCAFEBABE}) begin
      $display("@@@FAIL");
      $finish;
    end

    repeat(5) @(posedge sclk);

    // Test read operation signal behavior
    tx_data = {2'b00, 10'h0F0, 32'h00000000};

    @(negedge sclk);
    mosi = tx_data[43];
    cs_n = 0;

    for (i = 42; i >= 0; i = i - 1) begin
      @(negedge sclk);
      mosi = tx_data[i];

      // MISO should still be 0 during RX
      if (miso !== 1'b0) begin
        $display("@@@FAIL");
        $finish;
      end
    end

    @(negedge sclk);
    mosi = 0;

    @(posedge sclk);
    // Check only r_en is high for read
    if (!r_en || w_en) begin
      $display("@@@FAIL");
      $finish;
    end

    @(posedge sclk);
    // Memory signals should be clear after one cycle
    if (r_en || w_en) begin
      $display("@@@FAIL");
      $finish;
    end

    // Collect response
    for (i = 43; i >= 0; i = i - 1) begin
      @(posedge sclk);
      rx_data[i] = miso;
    end

    @(posedge sclk);
    cs_n = 1;

    $display("@@@PASS");
    $finish;
  end

endmodule