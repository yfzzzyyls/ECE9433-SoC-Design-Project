// Minimal SoC top: PicoRV32 core + behavioral SRAM preloaded from firmware hex.
module soc_top #(
    parameter int MEM_WORDS = 32'd32768,
    parameter string HEX_PATH = "third_party/picorv32/firmware/firmware.hex"
) (
    input  logic clk,
    input  logic rst_n,
    output logic trap
);

    // PicoRV32 native memory interface.
    logic        mem_valid;
    logic        mem_instr;
    logic        mem_ready;
    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [ 3:0] mem_wstrb;
    logic [31:0] mem_rdata;

    logic        mem_la_read;
    logic        mem_la_write;
    logic [31:0] mem_la_addr;
    logic [31:0] mem_la_wdata;
    logic [ 3:0] mem_la_wstrb;

    logic        pcpi_valid;
    logic [31:0] pcpi_insn;
    logic [31:0] pcpi_rs1;
    logic [31:0] pcpi_rs2;

    logic        trace_valid;
    logic [35:0] trace_data;
    logic [31:0] eoi;

    localparam int STACKADDR = MEM_WORDS * 4;

    picorv32 #(
        .ENABLE_COUNTERS   (0),
        .ENABLE_COUNTERS64 (0),
        .ENABLE_REGS_16_31 (1),
        .ENABLE_REGS_DUALPORT(1),
        .LATCHED_MEM_RDATA (0),
        .TWO_STAGE_SHIFT   (1),
        .BARREL_SHIFTER    (0),
        .TWO_CYCLE_COMPARE (0),
        .TWO_CYCLE_ALU     (0),
        .COMPRESSED_ISA    (1),
        .CATCH_MISALIGN    (1),
        .CATCH_ILLINSN     (1),
        .ENABLE_PCPI       (0),
        .ENABLE_MUL        (1),
        .ENABLE_FAST_MUL   (1),
        .ENABLE_DIV        (1),
        .ENABLE_IRQ        (0),
        .ENABLE_IRQ_QREGS  (0),
        .ENABLE_IRQ_TIMER  (0),
        .ENABLE_TRACE      (0),
        .REGS_INIT_ZERO    (0),
        .MASKED_IRQ        (32'h0000_0000),
        .LATCHED_IRQ       (32'hffff_ffff),
        .PROGADDR_RESET    (32'h0000_0000),
        .STACKADDR         (STACKADDR)
    ) u_cpu (
        .clk         (clk),
        .resetn      (rst_n),
        .trap        (trap),
        .mem_valid   (mem_valid),
        .mem_instr   (mem_instr),
        .mem_ready   (mem_ready),
        .mem_addr    (mem_addr),
        .mem_wdata   (mem_wdata),
        .mem_wstrb   (mem_wstrb),
        .mem_rdata   (mem_rdata),
        .mem_la_read (mem_la_read),
        .mem_la_write(mem_la_write),
        .mem_la_addr (mem_la_addr),
        .mem_la_wdata(mem_la_wdata),
        .mem_la_wstrb(mem_la_wstrb),
        .pcpi_valid  (pcpi_valid),
        .pcpi_insn   (pcpi_insn),
        .pcpi_rs1    (pcpi_rs1),
        .pcpi_rs2    (pcpi_rs2),
        .pcpi_wr     (1'b0),
        .pcpi_rd     (32'b0),
        .pcpi_wait   (1'b0),
        .pcpi_ready  (1'b0),
        .irq         (32'b0),
        .eoi         (eoi),
        .trace_valid (trace_valid),
        .trace_data  (trace_data)
    );

    // Basic synchronous memory model.
    logic [31:0] sram [0:MEM_WORDS-1];
    logic [31:0] mem_rdata_q;
    logic        mem_ready_q;

    initial begin : preload_hex
        if (HEX_PATH != "") begin
            $display("[%0t] Loading %s", $time, HEX_PATH);
            $readmemh(HEX_PATH, sram);
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_ready_q <= 1'b0;
            mem_rdata_q <= '0;
        end else begin
            mem_ready_q <= 1'b0;
            if (mem_valid) begin
                int unsigned word_addr;
                logic [31:0] read_word;

                word_addr = mem_addr[31:2];
                read_word = (word_addr < MEM_WORDS) ? sram[word_addr] : 32'h0000_0000;

                if (word_addr < MEM_WORDS && |mem_wstrb) begin
                    if (mem_wstrb[0]) read_word[7:0]   = mem_wdata[7:0];
                    if (mem_wstrb[1]) read_word[15:8]  = mem_wdata[15:8];
                    if (mem_wstrb[2]) read_word[23:16] = mem_wdata[23:16];
                    if (mem_wstrb[3]) read_word[31:24] = mem_wdata[31:24];
                    sram[word_addr] <= read_word;
                end

                mem_rdata_q <= read_word;
                mem_ready_q <= 1'b1;
            end
        end
    end

    assign mem_ready = mem_ready_q;
    assign mem_rdata = mem_rdata_q;

endmodule
