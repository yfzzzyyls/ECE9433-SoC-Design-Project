module spi_tb;
  // DUT-visible signals
  logic        sclk;
  logic        cs_n;
  logic        mosi;
  logic        miso;
  logic        r_en, w_en;
  logic [9:0]  addr;
  logic [31:0] data_o, data_i;

  // --- Instantiate DUT ---
  spi_sub dut(.*);

  // --- Tiny 1KB RAM (256 x 32b): active-high, comb read, sync write ---
  logic [31:0] mem [0:255];

  // write on posedge when w_en=1
  always_ff @(posedge sclk) if (!cs_n && w_en) mem[addr[7:0]] <= data_o;
  // comb read when r_en=1
  always_comb begin
    if (!cs_n && r_en) data_i = mem[addr[7:0]];
    else               data_i = 32'hXXXXXXXX;
  end

  // --- Clock ---
  initial begin sclk = 0; forever #5 sclk = ~sclk; end

  // --- SPI helpers (Mode-0): main shifts on negedge; sub samples on posedge ---
  task automatic tx44(input [43:0] word);
    integer i;
    begin
      cs_n = 0;
      for (i = 43; i >= 0; i--) begin
        @(negedge sclk); mosi = word[i];
        @(posedge sclk); /* sub samples here */
      end
    end
  endtask

  task automatic rx44(output [43:0] word);
    integer i; begin
      // spec: one posedge "memory" beat occurs here; main must hold mosi=0
      @(posedge sclk); mosi = 0;
      for (i = 43; i >= 0; i--) begin
        @(posedge sclk); word[i] = miso; // sample on posedge (sub drove on negedge)
      end
      @(posedge sclk); cs_n = 1; // done
    end
  endtask

  // --- Test sequence ---
  initial begin
    cs_n = 1; mosi = 0;
    repeat (2) @(posedge sclk);

    // Test 1: WRITE 0xDEADBEEF to addr 0x10 and verify echo
    logic [43:0] send, recv;
    send = {2'b01, 10'h010, 32'hDEADBEEF};
    tx44(send);
    rx44(recv);
    if (recv !== send) begin
      $display("ERROR: Write echo mismatch. exp=%h got=%h", send, recv);
      $display("@@@FAIL"); $finish;
    end

    // Test 2: READ addr 0x10 and verify data
    send = {2'b00, 10'h010, 32'hXXXXXXXX};
    tx44(send);
    rx44(recv);
    if (recv[43:32] !== {2'b00, 10'h010}) begin
      $display("ERROR: Read header mismatch. got=%h", recv[43:32]);
      $display("@@@FAIL"); $finish;
    end
    if (recv[31:0] !== 32'hDEADBEEF) begin
      $display("ERROR: Read data mismatch. exp=DEADBEEF got=%h", recv[31:0]);
      $display("@@@FAIL"); $finish;
    end

    $display("@@@PASS"); $finish;
  end
endmodule
