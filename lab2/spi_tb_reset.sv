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

    // Start a transaction but reset mid-way
    @(negedge sclk);
    cs_n = 0;
    tx_data = {2'b01, 10'h111, 32'h12345678};

    // Send partial message (20 bits)
    for (i = 43; i >= 24; i = i - 1) begin
      @(negedge sclk);
      mosi = tx_data[i];
    end

    // Reset by raising cs_n
    @(posedge sclk);
    cs_n = 1;

    // Verify no memory operation occurred
    @(posedge sclk);
    if (r_en || w_en) begin
      $display("@@@FAIL");
      $finish;
    end

    // Wait and start fresh transaction
    repeat(5) @(posedge sclk);

    // Complete transaction after reset
    @(negedge sclk);
    cs_n = 0;
    tx_data = {2'b01, 10'h222, 32'hDEADBEEF};

    for (i = 43; i >= 0; i = i - 1) begin
      @(negedge sclk);
      mosi = tx_data[i];
    end

    @(negedge sclk);
    mosi = 0;

    @(posedge sclk);
    if (!w_en) begin
      $display("@@@FAIL");
      $finish;
    end

    // Collect response
    for (i = 43; i >= 0; i = i - 1) begin
      @(posedge sclk);
      rx_data[i] = miso;
    end

    if (rx_data !== {2'b01, 10'h222, 32'hDEADBEEF}) begin
      $display("@@@FAIL");
      $finish;
    end

    @(posedge sclk);
    cs_n = 1;

    $display("@@@PASS");
    $finish;
  end

endmodule
