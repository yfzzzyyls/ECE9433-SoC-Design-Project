module ram #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 8,
    parameter DEPTH      = 1 << ADDR_WIDTH
) (
    input  logic                   clk,
    input  logic                   w_en,
    input  logic                   r_en,
    input  logic [ADDR_WIDTH-1:0]  addr,
    input  logic [DATA_WIDTH-1:0]  data_o,
    output logic [DATA_WIDTH-1:0]  data_i
);

    // Memory array
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Combinational read logic: updates immediately based on r_en
    always_comb begin
        if (r_en) begin
            data_i = mem[addr];
        end else begin
            data_i = '0;
        end
    end

    // Synchronous write logic: writes on posedge clk
    always_ff @(posedge clk) begin
        if (w_en) begin
            mem[addr] <= data_o;
        end
    end

endmodule
