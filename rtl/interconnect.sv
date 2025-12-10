// Simple address decoder/mux for one master and two slaves (SRAM/PEU) using
// the PicoRV32 native valid/ready interface.
module bus_interconnect #(
    parameter logic [31:0] SRAM_BASE = 32'h0000_0000,
    parameter logic [31:0] SRAM_MASK = 32'hF000_0000, // default: catch low region
    parameter logic [31:0] PEU_BASE  = 32'h1000_0000,
    parameter logic [31:0] PEU_MASK  = 32'hF000_0000  // default: catch 0x1xxx_xxxx
) (
    // Master side (CPU)
    input  logic        m_valid,
    input  logic        m_instr,
    output logic        m_ready,
    input  logic [31:0] m_addr,
    input  logic [31:0] m_wdata,
    input  logic [ 3:0] m_wstrb,
    output logic [31:0] m_rdata,

    // Slave: SRAM
    output logic        sram_valid,
    output logic        sram_instr,
    input  logic        sram_ready,
    output logic [31:0] sram_addr,
    output logic [31:0] sram_wdata,
    output logic [ 3:0] sram_wstrb,
    input  logic [31:0] sram_rdata,

    // Slave: PEU
    output logic        peu_valid,
    output logic        peu_instr,
    input  logic        peu_ready,
    output logic [31:0] peu_addr,
    output logic [31:0] peu_wdata,
    output logic [ 3:0] peu_wstrb,
    input  logic [31:0] peu_rdata
);

    // Decode
    wire hit_sram = ((m_addr & SRAM_MASK) == SRAM_BASE);
    wire hit_peu  = ((m_addr & PEU_MASK)  == PEU_BASE);

    // Drive slaves
    assign sram_valid = m_valid & hit_sram;
    assign sram_instr = m_instr;
    assign sram_addr  = m_addr;
    assign sram_wdata = m_wdata;
    assign sram_wstrb = m_wstrb;

    assign peu_valid  = m_valid & hit_peu;
    assign peu_instr  = m_instr;
    assign peu_addr   = m_addr;
    assign peu_wdata  = hit_peu ? m_wdata : 32'd0;
    assign peu_wstrb  = hit_peu ? m_wstrb : 4'b0;

    // Merge responses (priority: SRAM > PEU; unmatched returns ready=1 with zero data)
    always @(*) begin
        m_ready = 1'b0;
        m_rdata = 32'h0000_0000;
        if (hit_sram) begin
            m_ready = sram_ready;
            m_rdata = sram_rdata;
        end else if (hit_peu) begin
            m_ready = peu_ready;
            m_rdata = peu_rdata;
        end else if (m_valid) begin
            // Unmapped region: return immediately with zero data
            m_ready = 1'b1;
            m_rdata = 32'h0000_0000;
        end
    end

endmodule
