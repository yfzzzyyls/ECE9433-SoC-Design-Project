// Simple synchronous SRAM modeled with PicoRV32 native valid/ready interface.
module sram #(
    parameter int MEM_WORDS = 32'd32768
`ifndef SYNTHESIS
  , parameter string HEX_PATH = ""
`endif
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        mem_valid,
    input  logic        mem_instr,
    output logic        mem_ready,
    input  logic [31:0] mem_addr,
    input  logic [31:0] mem_wdata,
    input  logic [ 3:0] mem_wstrb,
    output logic [31:0] mem_rdata
);

`ifdef SYNTHESIS
    // Macro-backed SRAM for synthesis: TSMC16 512x45 single-port.
    localparam int unsigned SRAM_DEPTH = (MEM_WORDS < 512) ? MEM_WORDS : 512;

    logic [31:0] rdata_q;
    logic        ready_q;

    logic [44:0] sram_d;
    logic [44:0] sram_bweb;
    wire  [44:0] sram_q;
    wire         sram_ceb;
    wire         sram_web;
    wire  [8:0]  sram_addr;
`else
    // Behavioral model for simulation.
    logic [31:0] mem [0:MEM_WORDS-1];
    logic [31:0] rdata_q;
    logic        ready_q;
`endif

`ifndef SYNTHESIS
    // synopsys translate_off
    initial begin : preload_hex
        if (HEX_PATH != "") begin
            $display("[%0t] Loading %s", $time, HEX_PATH);
            $readmemh(HEX_PATH, mem);
        end
    end
    // synopsys translate_on
`endif

`ifdef SYNTHESIS
    // ---------------------------
    // Synthesis: map to hard macro
    // ---------------------------
    wire in_range;
    assign sram_addr = mem_addr[10:2];
    assign in_range  = mem_addr[31:2] < SRAM_DEPTH;

    assign sram_ceb = ~(mem_valid && in_range);
    assign sram_web = ~(mem_valid && in_range && |mem_wstrb);

    // Drive lower 32 bits; tie upper spare bits low.
    assign sram_d[31:0]  = mem_wdata;
    assign sram_d[44:32] = 13'b0;

    // Bit-wise active-low write enables; default no-write (all 1).
    always_comb begin
        sram_bweb = {45{1'b1}};
        if (mem_valid && in_range && |mem_wstrb) begin
            sram_bweb[7:0]    = {8{~mem_wstrb[0]}};
            sram_bweb[15:8]   = {8{~mem_wstrb[1]}};
            sram_bweb[23:16]  = {8{~mem_wstrb[2]}};
            sram_bweb[31:24]  = {8{~mem_wstrb[3]}};
            // Upper bits [44:32] remain 1 (not written).
        end
    end

    // Capture data/ready; assume single-cycle latency in this wrapper.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ready_q <= 1'b0;
            rdata_q <= '0;
        end else begin
            ready_q <= mem_valid && in_range;
            rdata_q <= sram_q[31:0];
        end
    end

    TS1N16ADFPCLLLVTA512X45M4SWSHOD u_sram_macro (
        .SLP    (1'b0),
        .DSLP   (1'b0),
        .SD     (1'b0),
        .PUDELAY(),
        .CLK    (clk),
        .CEB    (sram_ceb),
        .WEB    (sram_web),
        .A      (sram_addr),
        .D      (sram_d),
        .BWEB   (sram_bweb),
        .RTSEL  (2'b01),
        .WTSEL  (2'b01),
        .Q      (sram_q)
    );
`else
    // ---------------------------
    // Simulation: behavioral memory
    // ---------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ready_q <= 1'b0;
            rdata_q <= '0;
        end else begin
            ready_q <= 1'b0;
            if (mem_valid) begin
                int unsigned word_addr;
                logic [31:0] read_word;
                word_addr = mem_addr[31:2];
                read_word = (word_addr < MEM_WORDS) ? mem[word_addr] : 32'h0000_0000;

                if (word_addr < MEM_WORDS && |mem_wstrb) begin
                    if (mem_wstrb[0]) read_word[7:0]   = mem_wdata[7:0];
                    if (mem_wstrb[1]) read_word[15:8]  = mem_wdata[15:8];
                    if (mem_wstrb[2]) read_word[23:16] = mem_wdata[23:16];
                    if (mem_wstrb[3]) read_word[31:24] = mem_wdata[31:24];
                    mem[word_addr] <= read_word;
                end

                rdata_q <= read_word;
                ready_q <= 1'b1;
            end
        end
    end
`endif

    assign mem_ready = ready_q;
    assign mem_rdata = rdata_q;

endmodule
