//TOP module
module top;
  logic        sclk;
  logic        cs_n, mosi, miso;
  logic        r_en,  w_en;
  logic [9:0]  addr;
  logic [31:0] data_o, data_i;

  
  // student’s TB
  spi_tb tb (
    .sclk   (sclk),
    .r_en   (r_en),
    .w_en   (w_en),
    .addr   (addr),
    .data_o (data_o),
    .data_i (data_i)
  );

  // RAM 
  ram #(
    .DATA_WIDTH(32),
    .ADDR_WIDTH(8)
  ) memory (
    .clk   (sclk),
    .w_en   (w_en),
    .r_en   (r_en),
    .addr   (addr[7:0]),
    .data_o (data_o),
    .data_i (data_i)
  );


endmodule