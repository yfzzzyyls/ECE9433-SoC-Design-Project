module lfsr (
    input  logic       clk,
    input  logic       reset,    // active-high synchronous reset
    input  logic       load,     // load seed into LFSR
    input  logic       enable,   // enable LFSR shift
    input  logic [6:0] seed,     // 7-bit seed value
    output logic [6:0] lfsr_out  // current LFSR state
);

    logic [6:0] lfsr_reg;
    logic feedback_bit;

    // PRBS7: x^7 + x^6 + 1
    // Feedback from D6 and D5 (bits 6 and 5)
    assign feedback_bit = lfsr_reg[6] ^ lfsr_reg[5];
    
    // Output current LFSR state
    assign lfsr_out = lfsr_reg;

    always_ff @(posedge clk) begin
        if (reset) begin
            // Reset to all 1s
            lfsr_reg <= 7'b1111111;
        end
        else if (load) begin
            // Load seed value
            lfsr_reg <= seed;
        end
        else if (enable) begin
            // Left shift and insert feedback bit at LSB
            lfsr_reg <= {lfsr_reg[5:0], feedback_bit};
        end
        // else: retain current value
    end

endmodule