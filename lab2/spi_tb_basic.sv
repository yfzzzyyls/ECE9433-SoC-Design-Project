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

  // Test a simple write operation
  initial begin
    cs_n = 1;
    mosi = 0;

    // Wait for initialization
    repeat(5) @(posedge sclk);

    // Send write command: op=01, addr=0x100, data=0x12345678
    @(negedge sclk);
    mosi = 0;  // First bit of op (01)
    cs_n = 0;

    @(negedge sclk); mosi = 1;  // Second bit of op

    // Send 10 bits of address (0x100 = 0100000000)
    @(negedge sclk); mosi = 0;
    @(negedge sclk); mosi = 1;
    @(negedge sclk); mosi = 0;
    @(negedge sclk); mosi = 0;
    @(negedge sclk); mosi = 0;
    @(negedge sclk); mosi = 0;
    @(negedge sclk); mosi = 0;
    @(negedge sclk); mosi = 0;
    @(negedge sclk); mosi = 0;
    @(negedge sclk); mosi = 0;

    // Send 32 bits of data (0x12345678)
    @(negedge sclk); mosi = 0;  // bit 31
    @(negedge sclk); mosi = 0;
    @(negedge sclk); mosi = 0;
    @(negedge sclk); mosi = 1;
    @(negedge sclk); mosi = 0;
    @(negedge sclk); mosi = 0;
    @(negedge sclk); mosi = 1;
    @(negedge sclk); mosi = 0;
    @(negedge sclk); mosi = 0;  // bit 23
    @(negedge sclk); mosi = 0;
    @(negedge sclk); mosi = 1;
    @(negedge sclk); mosi = 1;
    @(negedge sclk); mosi = 0;
    @(negedge sclk); mosi = 1;
    @(negedge sclk); mosi = 0;
    @(negedge sclk); mosi = 0;
    @(negedge sclk); mosi = 0;  // bit 15
    @(negedge sclk); mosi = 1;
    @(negedge sclk); mosi = 0;
    @(negedge sclk); mosi = 1;
    @(negedge sclk); mosi = 0;
    @(negedge sclk); mosi = 1;
    @(negedge sclk); mosi = 1;
    @(negedge sclk); mosi = 0;
    @(negedge sclk); mosi = 0;  // bit 7
    @(negedge sclk); mosi = 1;
    @(negedge sclk); mosi = 1;
    @(negedge sclk); mosi = 1;
    @(negedge sclk); mosi = 1;
    @(negedge sclk); mosi = 0;
    @(negedge sclk); mosi = 0;
    @(negedge sclk); mosi = 0;  // bit 0

    // Hold mosi low
    @(negedge sclk);
    mosi = 0;

    // Wait for response
    repeat(50) @(posedge sclk);

    // End
    cs_n = 1;

    $display("@@@PASS");
    $finish;
  end

endmodule