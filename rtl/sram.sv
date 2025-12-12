// Simple synchronous SRAM wrapper.
// For SYNTHESIS: instantiates TSMC 16nm SRAM macro
// For SIMULATION: uses behavioral register file with hex preload
module sram #(
    parameter int MEM_WORDS = 32'd512
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
    // ---------------------------
    // SYNTHESIS: TSMC 16nm SRAM macro
    // TS1N16ADFPCLLLVTA512X45M4SWSHOD
    // 512 words x 45 bits (we use 32 data + 4 byte-enable + padding)
    // ---------------------------
    logic        sram_clk;
    logic        sram_ceb;   // Chip enable (active low)
    logic        sram_web;   // Write enable (active low)
    logic [8:0]  sram_a;     // Address (9 bits for 512 words)
    logic [44:0] sram_d;     // Write data (45 bits)
    logic [44:0] sram_bweb;  // Bit write enable (active low)
    logic [44:0] sram_q;     // Read data (45 bits)

    logic [31:0] rdata_q;
    logic        ready_q;

    // SRAM control signals
    assign sram_clk = clk;
    assign sram_ceb = ~mem_valid;  // Active low chip enable
    assign sram_web = ~(|mem_wstrb);  // Active low write enable
    assign sram_a   = mem_addr[10:2];  // Word address (bits [10:2] for 512 words)

    // Write data - pack into 45 bits (use lower 32 bits)
    assign sram_d = {13'b0, mem_wdata};

    // Byte write enables - active low, expand 4-bit strobe to 45 bits
    assign sram_bweb = {13'hFFFF,
                        {8{~mem_wstrb[3]}},
                        {8{~mem_wstrb[2]}},
                        {8{~mem_wstrb[1]}},
                        {8{~mem_wstrb[0]}}};

    // Instantiate TSMC SRAM macro
    TS1N16ADFPCLLLVTA512X45M4SWSHOD u_sram_macro (
        .CLK   (sram_clk),
        .CEB   (sram_ceb),
        .WEB   (sram_web),
        .A     (sram_a),
        .D     (sram_d),
        .BWEB  (sram_bweb),
        .RTSEL (2'b01),
        .WTSEL (2'b01),
        .Q     (sram_q)
    );

    // Read data - extract lower 32 bits
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ready_q <= 1'b0;
            rdata_q <= 32'b0;
        end else begin
            ready_q <= mem_valid;
            if (mem_valid && !sram_web) begin
                // Write operation - read back written data
                rdata_q <= mem_wdata;
            end else begin
                // Read operation - get data from SRAM
                rdata_q <= sram_q[31:0];
            end
        end
    end

    assign mem_ready = ready_q;
    assign mem_rdata = rdata_q;

`else
    // ---------------------------
    // SIMULATION: Behavioral model with hex preload
    // ---------------------------
    logic [31:0] mem [0:MEM_WORDS-1];
    logic [31:0] rdata_q;
    logic        ready_q;

    // synopsys translate_off
    initial begin : preload_hex
        if (HEX_PATH != "") begin
            $display("[%0t] Loading %s", $time, HEX_PATH);
            $readmemh(HEX_PATH, mem);
        end
    end
    // synopsys translate_on

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ready_q <= 1'b0;
            rdata_q <= '0;
        end else begin
            ready_q <= 1'b0;
            if (mem_valid) begin
                logic [31:0] word_addr;
                logic [31:0] read_word;
                word_addr = mem_addr[31:2];

                if (word_addr < MEM_WORDS) begin
                    read_word = mem[word_addr[8:0]];

                    if (|mem_wstrb) begin
                        if (mem_wstrb[0]) read_word[7:0]   = mem_wdata[7:0];
                        if (mem_wstrb[1]) read_word[15:8]  = mem_wdata[15:8];
                        if (mem_wstrb[2]) read_word[23:16] = mem_wdata[23:16];
                        if (mem_wstrb[3]) read_word[31:24] = mem_wdata[31:24];
                        mem[word_addr[8:0]] <= read_word;
                    end

                    rdata_q <= read_word;
                    ready_q <= 1'b1;
                end else begin
                    rdata_q <= 32'h0000_0000;
                    ready_q <= 1'b1;
                end
            end
        end
    end

    assign mem_ready = ready_q;
    assign mem_rdata = rdata_q;
`endif

endmodule
