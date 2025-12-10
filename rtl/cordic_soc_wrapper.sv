`timescale 1ns/1ps

module cordic_soc_wrapper #(
    parameter int WIDTH = 32
)(
    input  logic clk,
    input  logic rst_n,

    // === CPU Bus Interface (Standard Valid/Ready) ===
    input  logic        bus_valid,    // Request signal from CPU
    output logic        bus_ready,    // Handshake signal to CPU
    
    input  logic        bus_write_en, // Write enable (derived from |wstrb)
    input  logic [4:0]  bus_addr,     // 5-bit Address Offset
    input  logic [31:0] bus_wdata,    // Write Data
    output logic [31:0] bus_rdata     // Read Data
);

    // =========================================================
    // 1. Built-in Bus Handshake Logic (Glue Logic)
    // =========================================================
    logic bus_ack_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bus_ack_reg <= 1'b0;
        end else begin
            // Assert ACK when request received (valid) and not yet acknowledged.
            // CPU will deassert 'valid' upon seeing 'ready/ack'.
            bus_ack_reg <= bus_valid && !bus_ack_reg;
        end
    end

    // Connect internal ACK to bus Ready
    assign bus_ready = bus_ack_reg;

    // =========================================================
    // 2. Internal Logic
    // =========================================================
    logic [31:0] x_in_reg, y_in_reg, angle_in_reg;
    logic valid_atan, valid_sincos;

    logic [31:0] res_phase, res_cos, res_sin;
    logic out_valid_atan, out_valid_sincos;
    
    logic [31:0] reg_res_phase, reg_res_cos, reg_res_sin;

    // Internal Write Trigger:
    // Only write if (Bus Valid) AND (Write Op) AND (Handshake not done)
    logic internal_write_trigger;
    assign internal_write_trigger = bus_valid && bus_write_en && !bus_ack_reg;

    // Input Registers & Trigger Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y_in_reg     <= '0;
            x_in_reg     <= '0; 
            angle_in_reg <= '0; 
            valid_atan   <= 0;
            valid_sincos <= 0;
        end else begin
            valid_atan   <= 0; // Auto-clear triggers
            valid_sincos <= 0;

            if (internal_write_trigger) begin
                case (bus_addr)
                    5'h00: begin 
                        x_in_reg   <= bus_wdata;
                        valid_atan <= 1'b1; // Trigger Atan2
                    end
                    5'h04: begin 
                        y_in_reg   <= bus_wdata;
                    end
                    5'h08: begin 
                        angle_in_reg <= bus_wdata;
                        valid_sincos <= 1'b1; // Trigger SinCos
                    end
                    default: ;
                endcase
            end
        end
    end

    // =========================================================
    // 3. Core Instantiation
    // =========================================================
    cordic_core_atan2 #(.WIDTH(WIDTH), .ITERATIONS(16)) u_core_atan2 (
        .clk(clk), .rst_n(rst_n),
        .valid_in(valid_atan),
        .x_in(x_in_reg), .y_in(y_in_reg),
        .valid_out(out_valid_atan), .phase_out(res_phase)
    );

    cordic_core_sincos #(.WIDTH(WIDTH), .ITERATIONS(16)) u_core_sincos (
        .clk(clk), .rst_n(rst_n),
        .valid_in(valid_sincos), .angle_in(angle_in_reg),
        .valid_out(out_valid_sincos), .cos_out(res_cos), .sin_out(res_sin)
    );
    
    // =========================================================
    // 4. Result Latching
    // =========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            reg_res_phase <= '0; reg_res_cos <= '0; reg_res_sin <= '0;
        end else begin
            if (out_valid_atan)   reg_res_phase <= res_phase;
            if (out_valid_sincos) begin 
                reg_res_cos <= res_cos; 
                reg_res_sin <= res_sin; 
            end
        end
    end

    // =========================================================
    // 5. Read Logic
    // =========================================================
    always_comb begin
        case (bus_addr)
            5'h0C: bus_rdata = reg_res_phase;
            5'h10: bus_rdata = reg_res_cos;
            5'h14: bus_rdata = reg_res_sin;
            default: bus_rdata = 32'd0;
        endcase
    end

endmodule