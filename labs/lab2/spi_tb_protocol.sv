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
  logic last_miso;

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
    last_miso = 0;

    repeat(5) @(posedge sclk);

    // Test protocol: miso must be 0 during Main's transmission
    @(negedge sclk);
    cs_n = 0;
    tx_data = {2'b01, 10'h123, 32'hABCDEF01};

    for (i = 43; i >= 0; i = i - 1) begin
      @(negedge sclk);
      mosi = tx_data[i];

      // Check miso stays low during Main's message
      if (miso !== 1'b0) begin
        $display("@@@FAIL");
        $finish;
      end
    end

    @(negedge sclk);
    mosi = 0;

    // Memory pulse should happen on next posedge
    @(posedge sclk);
    if (!w_en && !r_en) begin
      $display("@@@FAIL");
      $finish;
    end

    // Check that only one of r_en or w_en is high
    if (r_en && w_en) begin
      $display("@@@FAIL");
      $finish;
    end

    // Verify memory pulse is exactly one cycle
    @(posedge sclk);
    if (r_en || w_en) begin
      $display("@@@FAIL");
      $finish;
    end

    // Collect response and verify Main holds mosi=0
    for (i = 43; i >= 0; i = i - 1) begin
      @(posedge sclk);
      rx_data[i] = miso;

      // Check Main holds mosi low during Sub's response
      if (mosi !== 1'b0) begin
        $display("@@@FAIL");
        $finish;
      end
    end

    @(posedge sclk);
    cs_n = 1;

    // Test read operation protocol
    repeat(5) @(posedge sclk);

    @(negedge sclk);
    cs_n = 0;
    tx_data = {2'b00, 10'h200, 32'h00000000};

    for (i = 43; i >= 0; i = i - 1) begin
      @(negedge sclk);
      mosi = tx_data[i];

      if (miso !== 1'b0) begin
        $display("@@@FAIL");
        $finish;
      end
    end

    @(negedge sclk);
    mosi = 0;

    @(posedge sclk);
    if (!r_en) begin
      $display("@@@FAIL");
      $finish;
    end
    if (w_en) begin
      $display("@@@FAIL");
      $finish;
    end

    // Collect response
    for (i = 43; i >= 0; i = i - 1) begin
      @(posedge sclk);
      rx_data[i] = miso;
    end

    // Verify opcode and address are echoed
    if (rx_data[43:32] !== {2'b00, 10'h200}) begin
      $display("@@@FAIL");
      $finish;
    end

    @(posedge sclk);
    cs_n = 1;

    $display("@@@PASS");
    $finish;
  end

endmodule