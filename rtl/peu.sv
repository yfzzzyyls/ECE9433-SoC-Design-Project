// PEU accelerator stub with memory-mapped registers.
module peu #(
    parameter logic [31:0] BASE_ADDR = 32'h1000_0000
) (
    input  logic        clk,
    input  logic        rst_n,
    // Native valid/ready interface
    input  logic        mem_valid,
    input  logic        mem_instr,
    output logic        mem_ready,
    input  logic [31:0] mem_addr,
    input  logic [31:0] mem_wdata,
    input  logic [ 3:0] mem_wstrb,
    output logic [31:0] mem_rdata
);

    // Registers
    logic [31:0] reg_src0;
    logic [31:0] reg_src1;
    logic [31:0] reg_ctrl;
    logic [31:0] reg_status;
    logic [31:0] reg_result;

    // Offsets
    localparam logic [31:0] OFF_SRC0   = 32'h0;
    localparam logic [31:0] OFF_SRC1   = 32'h4;
    localparam logic [31:0] OFF_CTRL   = 32'h8;
    localparam logic [31:0] OFF_STATUS = 32'hC;
    localparam logic [31:0] OFF_RESULT = 32'h10;

    // Decode a word-aligned offset within the PEU window.
    wire [31:0] rel_addr = mem_addr - BASE_ADDR;

    // Simple one-cycle response
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_src0   <= '0;
            reg_src1   <= '0;
            reg_ctrl   <= '0;
            reg_status <= '0;
            reg_result <= '0;
            mem_ready  <= 1'b0;
            mem_rdata  <= '0;
        end else begin
            mem_ready <= 1'b0;

            if (mem_valid) begin
                // Handle write
                if (|mem_wstrb) begin
                    unique case (rel_addr)
                        OFF_SRC0:   reg_src0 <= mem_wdata;
                        OFF_SRC1:   reg_src1 <= mem_wdata;
                        OFF_CTRL:   reg_ctrl <= mem_wdata;
                        default: ;
                    endcase
                end

                // Handle read
                unique case (rel_addr)
                    OFF_SRC0:   mem_rdata <= reg_src0;
                    OFF_SRC1:   mem_rdata <= reg_src1;
                    OFF_CTRL:   mem_rdata <= reg_ctrl;
                    OFF_STATUS: mem_rdata <= reg_status;
                    OFF_RESULT: mem_rdata <= reg_result;
                    default:    mem_rdata <= 32'h0000_0000;
                endcase

                mem_ready <= 1'b1;

                // Simple "start" detection and immediate computation (stub: add)
                if (|mem_wstrb && rel_addr == OFF_CTRL && mem_wdata[0]) begin
                    reg_result <= reg_src0 + reg_src1;
                    reg_status <= 32'h1; // done bit
                end

                // Clear done if ctrl written without start bit
                if (|mem_wstrb && rel_addr == OFF_CTRL && !mem_wdata[0]) begin
                    reg_status <= 32'h0;
                end
            end
        end
    end

endmodule
