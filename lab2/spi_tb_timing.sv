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
  integer cycles_since_last_bit;
  logic mem_pulse_seen;

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
    mem_pulse_seen = 0;
    cycles_since_last_bit = 0;

    repeat(5) @(posedge sclk);

    // Test memory pulse timing
    tx_data = {2'b01, 10'h0A5, 32'h5A5A5A5A};

    @(negedge sclk);
    mosi = tx_data[43];
    cs_n = 0;

    // Send 43 more bits
    for (i = 42; i >= 0; i = i - 1) begin
      @(negedge sclk);
      mosi = tx_data[i];
    end

    // After last bit sent, hold mosi low
    @(negedge sclk);
    mosi = 0;

    // Memory pulse should occur on NEXT posedge (exactly 1 cycle after last bit)
    @(posedge sclk);
    cycles_since_last_bit = 1;
    if (w_en) begin
      mem_pulse_seen = 1;
      // Good - memory pulse at right time
    end else begin
      $display("@@@FAIL");  // No memory pulse when expected
      $finish;
    end

    // Memory pulse should be exactly 1 cycle
    @(posedge sclk);
    if (w_en || r_en) begin
      $display("@@@FAIL");  // Memory pulse too long
      $finish;
    end

    // Collect response
    for (i = 43; i >= 0; i = i - 1) begin
      @(posedge sclk);
      rx_data[i] = miso;
    end

    @(posedge sclk);
    cs_n = 1;

    repeat(5) @(posedge sclk);

    // Test read operation timing
    tx_data = {2'b00, 10'h0A5, 32'h00000000};
    mem_pulse_seen = 0;

    @(negedge sclk);
    mosi = tx_data[43];
    cs_n = 0;

    for (i = 42; i >= 0; i = i - 1) begin
      @(negedge sclk);
      mosi = tx_data[i];
    end

    @(negedge sclk);
    mosi = 0;

    // Check read pulse timing
    @(posedge sclk);
    if (r_en) begin
      mem_pulse_seen = 1;
    end else begin
      $display("@@@FAIL");  // No read pulse
      $finish;
    end

    // Should be exactly 1 cycle
    @(posedge sclk);
    if (r_en || w_en) begin
      $display("@@@FAIL");  // Pulse too long
      $finish;
    end

    // Collect and verify response
    for (i = 43; i >= 0; i = i - 1) begin
      @(posedge sclk);
      rx_data[i] = miso;
    end

    // Check we read back what we wrote
    if (rx_data[31:0] !== 32'h5A5A5A5A) begin
      $display("@@@FAIL");
      $finish;
    end

    @(posedge sclk);
    cs_n = 1;

    $display("@@@PASS");
    $finish;
  end

endmodule