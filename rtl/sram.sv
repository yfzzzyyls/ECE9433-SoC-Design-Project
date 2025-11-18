// Simple synchronous SRAM modeled with PicoRV32 native valid/ready interface.
module sram #(
    parameter int MEM_WORDS = 32'd32768,
    parameter string HEX_PATH = ""
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

    logic [31:0] mem [0:MEM_WORDS-1];
    logic [31:0] rdata_q;
    logic        ready_q;

    initial begin : preload_hex
        if (HEX_PATH != "") begin
            $display("[%0t] Loading %s", $time, HEX_PATH);
            $readmemh(HEX_PATH, mem);
        end
    end

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

    assign mem_ready = ready_q;
    assign mem_rdata = rdata_q;

endmodule
