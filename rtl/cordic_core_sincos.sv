`timescale 1ns/1ps

module cordic_core_sincos #(
    parameter int WIDTH = 32,
    parameter int FRAC_BITS = 16,
    parameter int ITERATIONS = 16
)(
    input  logic clk,
    input  logic rst_n,
    input  logic valid_in,
    input  logic signed [WIDTH-1:0] angle_in,
    
    output logic valid_out,
    output logic signed [WIDTH-1:0] cos_out,
    output logic signed [WIDTH-1:0] sin_out
);

    // Gain Factor K ~ 0.60725
    localparam signed [WIDTH-1:0] K_VALUE = 32'd39797;
    
    // ASIC Lookup Table Constants
    localparam logic signed [WIDTH-1:0] ATAN_CONST [0:19] = '{
        32'd51472, 32'd30386, 32'd16055, 32'd8150, 32'd4091, 
        32'd2047,  32'd1024,  32'd512,   32'd256,  32'd128,  
        32'd64,    32'd32,    32'd16,    32'd8,    32'd4,    
        32'd2,     32'd1,     32'd1,     32'd0,    32'd0
    };

    logic signed [WIDTH-1:0] x_pipe [0:ITERATIONS];
    logic signed [WIDTH-1:0] y_pipe [0:ITERATIONS];
    logic signed [WIDTH-1:0] z_pipe [0:ITERATIONS];
    logic                    v_pipe [0:ITERATIONS];

    // Stage 0: Initialization
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_pipe[0] <= '0; y_pipe[0] <= '0; z_pipe[0] <= '0; v_pipe[0] <= 1'b0;
        end else begin
            v_pipe[0] <= valid_in;
            if (valid_in) begin
                x_pipe[0] <= K_VALUE; // Initialize X with Gain K
                y_pipe[0] <= '0;
                z_pipe[0] <= angle_in;
            end
        end
    end

    // Pipeline Stages (Rotation Mode)
    genvar i;
    generate
        for (i = 0; i < ITERATIONS; i++) begin : stage
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    x_pipe[i+1] <= '0; 
                    y_pipe[i+1] <= '0; 
                    z_pipe[i+1] <= '0; 
                    v_pipe[i+1] <= 1'b0;
                end else begin
                    v_pipe[i+1] <= v_pipe[i];
                    
                    // Rotate to minimize Z (Angle)
                    if (z_pipe[i] >= 0) begin
                        x_pipe[i+1] <= x_pipe[i] - (y_pipe[i] >>> i);
                        y_pipe[i+1] <= y_pipe[i] + (x_pipe[i] >>> i);
                        z_pipe[i+1] <= z_pipe[i] - ATAN_CONST[i];
                    end else begin
                        x_pipe[i+1] <= x_pipe[i] + (y_pipe[i] >>> i);
                        y_pipe[i+1] <= y_pipe[i] - (x_pipe[i] >>> i);
                        z_pipe[i+1] <= z_pipe[i] + ATAN_CONST[i];
                    end
                end
            end
        end
    endgenerate

    assign valid_out = v_pipe[ITERATIONS];
    assign cos_out   = x_pipe[ITERATIONS];
    assign sin_out   = y_pipe[ITERATIONS];

endmodule