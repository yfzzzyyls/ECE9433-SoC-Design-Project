// Minimal SoC top: PicoRV32 core + behavioral SRAM preloaded from firmware hex.
module soc_top #(
    parameter int MEM_WORDS = 32'd512
`ifndef SYNTHESIS
    , parameter string HEX_PATH = "firmware/peu_test/peu_test.hex"
`endif
) (
    input  logic clk,
    input  logic rst_n,
    output logic trap
);

    // PicoRV32 native memory interface (master).
    logic        mem_valid;
    logic        mem_instr;
    logic        mem_ready;
    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [ 3:0] mem_wstrb;
    logic [31:0] mem_rdata;

    // To SRAM slave
    logic        sram_valid;
    logic        sram_instr;
    logic        sram_ready;
    logic [31:0] sram_addr;
    logic [31:0] sram_wdata;
    logic [ 3:0] sram_wstrb;
    logic [31:0] sram_rdata;

    // To PEU slave
    logic        peu_valid;
    logic        peu_instr;
    logic        peu_ready;
    logic [31:0] peu_addr;
    logic [31:0] peu_wdata;
    logic [ 3:0] peu_wstrb;
    logic [31:0] peu_rdata;

    // Unused PicoRV32 ports
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
        .mem_ready   (mem_ready), // input
        .mem_addr    (mem_addr),  
        .mem_wdata   (mem_wdata),
        .mem_wstrb   (mem_wstrb),
        .mem_rdata   (mem_rdata), // input
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

    // Interconnect
    bus_interconnect u_ic (
        .m_valid   (mem_valid),
        .m_instr   (mem_instr),
        .m_ready   (mem_ready),
        .m_addr    (mem_addr),
        .m_wdata   (mem_wdata),
        .m_wstrb   (mem_wstrb),
        .m_rdata   (mem_rdata),
        .sram_valid(sram_valid),
        .sram_instr(sram_instr),
        .sram_ready(sram_ready),
        .sram_addr (sram_addr),
        .sram_wdata(sram_wdata),
        .sram_wstrb(sram_wstrb),
        .sram_rdata(sram_rdata),
        .peu_valid (peu_valid),
        .peu_instr (peu_instr),
        .peu_ready (peu_ready),
        .peu_addr  (peu_addr),
        .peu_wdata (peu_wdata),
        .peu_wstrb (peu_wstrb),
        .peu_rdata (peu_rdata)
    );

    // SRAM slave
    sram #(
        .MEM_WORDS(MEM_WORDS)
    `ifndef SYNTHESIS
        , .HEX_PATH (HEX_PATH)
    `endif
    ) u_sram (
        .clk      (clk),
        .rst_n    (rst_n),
        .mem_valid(sram_valid),
        .mem_instr(sram_instr),
        .mem_ready(sram_ready),
        .mem_addr (sram_addr),
        .mem_wdata(sram_wdata),
        .mem_wstrb(sram_wstrb),
        .mem_rdata(sram_rdata)
    );

    cordic_soc_wrapper #(
        .WIDTH(32)
    ) u_cordic (
        .clk         (clk),
        .rst_n       (rst_n),
        
        // Standard Bus Handshake
        .bus_valid   (peu_valid),   // IN: Request from CPU
        .bus_ready   (peu_ready),   // OUT: Acknowledgment from Wrapper
        
        // Control Signals
        .bus_write_en(|peu_wstrb),  // Logic high if any byte write strobe is active
        .bus_addr    (peu_addr[4:0]), // Map 32-bit byte address to 5-bit offset
        
        // Data Path
        .bus_wdata   (peu_wdata),
        .bus_rdata   (peu_rdata)
    );

// =============================================================
    // Simulation-Only Terminal Printer (Magic Address)
    // =============================================================
    // 这是一个“虚拟硬件”，综合时会被忽略，仅在 VCS 仿真时有效。
    // 原理：Interconnect 会对未知地址自动回复 ready，所以 CPU 不会卡死。
    // 我们只需要在这里“偷窥”总线，发现往 0x20000000 写数据，就打印出来。
    

`ifndef SYNTHESIS
    initial begin
        // 指定输出文件名
        $dumpfile("cordic_debug.vcd");
        
        // 指定要记录的层级：
        // 0 表示记录该模块及其下所有子模块
        // u_cordic 是我们在 soc_top 里实例化的名字
        $dumpvars(0, soc_top);
        
        // 如果你也想看 CPU 的总线动作，可以把下面这行解注：
        // $dumpvars(0, u_ic); 
    end
`endif

endmodule
