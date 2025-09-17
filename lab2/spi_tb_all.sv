module spi_tb (
  output logic        sclk,
  output logic        r_en,
  output logic        w_en,
  output logic [9:0]  addr,
  output logic [31:0] data_o,
  input  logic [31:0] data_i
);

  logic cs_n, mosi, miso;

  logic        r_en_i, w_en_i;
  logic [9:0]  addr_i;
  logic [31:0] data_o_i;

  assign r_en   = r_en_i;
  assign w_en   = w_en_i;
  assign addr   = addr_i;
  assign data_o = data_o_i;

  logic [1:0]  OP_WRITE, OP_READ;
  logic [9:0]  A10;
  logic [9:0]  A11;
  logic [31:0] D32;
  logic [43:0] tx_msg, rx_msg;

  spi_sub dut (
    .sclk   (sclk),
    .cs_n   (cs_n),
    .mosi   (mosi),
    .miso   (miso),
    .r_en   (r_en_i),
    .w_en   (w_en_i),
    .addr   (addr_i),
    .data_o (data_o_i),
    .data_i (data_i)
  );

  initial begin
    sclk = 1'b0;
    forever #5 sclk = ~sclk;
  end

  task automatic spi_send_44(input logic [43:0] msg);
    int i;
    begin
      @(negedge sclk);
      #2;
      cs_n <= 1'b0;
      for (i = 43; i >= 0; i--) begin
        mosi <= msg[i];
        @(negedge sclk);
      end
      mosi <= 1'b0;
    end
  endtask

  task automatic spi_recv_44(output logic [43:0] resp);
    int i;
    begin
      resp = '0;
      @(negedge sclk);
      for (i = 43; i >= 0; i--) begin
        @(posedge sclk);
        resp[i] = miso;
      end
    end
  endtask

  function automatic logic [43:0] mk_msg(input logic [1:0] op,
                                         input logic [9:0] a10,
                                         input logic [31:0] d32);
    mk_msg = {op, a10, d32};
  endfunction

  initial begin
    cs_n = 1'b1;
    mosi = 1'b0;
    repeat (4) @(posedge sclk);

    OP_WRITE = 2'b01;
    OP_READ  = 2'b00;
    A10      = {2'b00, 8'h34};
    A11      = {2'b00, 8'h35};
    D32      = 32'hCAFE_BABE;

    tx_msg = mk_msg(OP_WRITE, A11, D32);
    spi_send_44(tx_msg);
    @(negedge sclk); 
    spi_recv_44(rx_msg);

    if (rx_msg !== tx_msg) begin
      $display("@@@FAIL");
      $display("Write echo mismatch. TX=%h RX=%h", tx_msg, rx_msg);
      $finish;
    end

    rx_msg = '0; 

    tx_msg = mk_msg(OP_WRITE, A10, D32);
    spi_send_44(tx_msg);
    @(negedge sclk); 
    spi_recv_44(rx_msg);

    if (rx_msg !== tx_msg) begin
      $display("@@@FAIL");
      $display("Write echo mismatch. TX=%h RX=%h", tx_msg, rx_msg);
      $finish;
    end
    cs_n = 1'b1;
    repeat (2) @(posedge sclk);
    rx_msg = '0; 

    tx_msg = mk_msg(OP_READ, A10, 32'h0000_0000);
    spi_send_44(tx_msg);
    @(negedge sclk); 
    spi_recv_44(rx_msg);

    if (rx_msg[43:42] !== OP_READ ||
        rx_msg[41:32] !== A10     ||
        rx_msg[31:0]  !== D32) begin
      $display("@@@FAIL");
      $display("Read response mismatch. EXP op=%b addr=%h data=%h, GOT %b %h %h",
               OP_READ, A10, D32,
               rx_msg[43:42], rx_msg[41:32], rx_msg[31:0]);
      $finish;
    end

    $display("@@@PASS");
    $finish;
  end

endmodule
