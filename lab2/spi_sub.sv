module spi_sub (
    // SPI signals
    input  logic        sclk,
    input  logic        cs_n,
    input  logic        mosi,
    output logic        miso,

    // Memory signals
    output logic        r_en,
    output logic        w_en,
    output logic [9:0]  addr,
    output logic [31:0] data_o,
    input  logic [31:0] data_i
);

    // Internal registers
    logic [43:0] rx_shift_reg;     // Receive shift register
    logic [43:0] tx_shift_reg;     // Transmit shift register
    logic [5:0]  bit_counter;      // Counts 0-43 for receive
    logic [5:0]  tx_bit_counter;   // Separate counter for transmit
    logic [43:0] message_buffer;   // Store complete received message

    // Registered memory interface signals
    logic [9:0]  addr_reg;          // Registered address for stable RAM access
    logic [31:0] data_o_reg;        // Registered data out for stable RAM writes

    // State machine - 4 states for proper timing
    typedef enum logic [1:0] {
        IDLE     = 2'b00,
        RECEIVE  = 2'b01,
        MEMORY   = 2'b10,  // Access memory after receiving
        TRANSMIT = 2'b11
    } state_t;

    state_t state, next_state;

    // Control signals
    logic message_complete;
    logic response_start;
    logic is_read_op;
    logic is_write_op;
    logic mem_phase;         // One-cycle strobe for memory access
    logic [43:0] full_msg;   // Complete message for decoding

    // Decode operation type
    assign is_read_op  = (message_buffer[43:42] == 2'b00);
    assign is_write_op = (message_buffer[43:42] == 2'b01);

    // Message complete when we've received 44 bits
    assign message_complete = (state == RECEIVE) && (bit_counter == 6'd43);

    // Memory interface signals - use registered versions for stability
    assign addr = addr_reg;
    assign data_o = data_o_reg;

    // Generate mem_phase strobe - active for one cycle when entering MEMORY state
    always_ff @(posedge sclk) begin
        if (cs_n) begin
            mem_phase <= 1'b0;
        end else begin
            // Raise mem_phase when transitioning from RECEIVE to MEMORY
            mem_phase <= (state == RECEIVE) && (next_state == MEMORY);
        end
    end

    // Memory control - registered one-shot pulses synchronized with mem_phase
    always_ff @(posedge sclk) begin
        if (cs_n) begin
            r_en <= 1'b0;
            w_en <= 1'b0;
        end else begin
            // Use mem_phase for clean one-cycle pulse
            r_en <= mem_phase && (message_buffer[43:42] == 2'b00);  // READ
            w_en <= mem_phase && (message_buffer[43:42] == 2'b01);  // WRITE
        end
    end

    // State machine - sequential part
    always_ff @(posedge sclk) begin
        if (cs_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    // State machine - combinational part
    always_comb begin
        next_state = state;

        case (state)
            IDLE: begin
                if (!cs_n)
                    next_state = RECEIVE;
            end

            RECEIVE: begin
                if (bit_counter == 6'd43)
                    next_state = MEMORY;  // Go to MEMORY state after receiving
            end

            MEMORY: begin
                next_state = TRANSMIT;  // Single cycle for memory access
            end

            TRANSMIT: begin
                if (tx_bit_counter == 6'd43)
                    next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase
    end

    // Receive logic - sample on posedge
    always_ff @(posedge sclk) begin
        if (cs_n) begin
            rx_shift_reg <= 44'b0;
            bit_counter <= 6'b0;
            tx_bit_counter <= 6'b0;
            message_buffer <= 44'b0;
            addr_reg <= 10'b0;
            data_o_reg <= 32'b0;
        end else begin
            if (state == RECEIVE) begin
                // Shift in MOSI bit (MSB first)
                rx_shift_reg <= {rx_shift_reg[42:0], mosi};
                bit_counter <= bit_counter + 1'b1;

                // Store complete message when we have all 44 bits
                if (bit_counter == 6'd43) begin
                    // Form the complete 44-bit message including the current bit
                    full_msg = {rx_shift_reg[42:0], mosi};  // Blocking assignment
                    message_buffer <= full_msg;              // Store for later states

                    // Also latch address and data for stable memory access
                    addr_reg <= full_msg[41:32];            // 10-bit address
                    data_o_reg <= full_msg[31:0];           // 32-bit data
                end
            end else if (state == MEMORY) begin
                // Initialize tx counter for transmit phase
                tx_bit_counter <= 6'b0;
            end else if (state == TRANSMIT) begin
                // Increment tx counter after each bit sent
                if (tx_bit_counter < 6'd43) begin
                    tx_bit_counter <= tx_bit_counter + 1'b1;
                end
            end
        end
    end

    // Prepare transmit data - load when entering TRANSMIT state
    always_ff @(posedge sclk) begin
        if (cs_n) begin
            tx_shift_reg <= 44'b0;
        end else if (state == MEMORY && next_state == TRANSMIT) begin
            // Load transmit register when transitioning to TRANSMIT
            // At this point, data_i is valid from the MEMORY state
            if (is_read_op) begin
                // For read: return opcode, address, and data from RAM
                tx_shift_reg <= {message_buffer[43:32], data_i};
            end else begin
                // For write: echo the complete message
                tx_shift_reg <= message_buffer;
            end
        end
        // Note: tx_shift_reg doesn't shift - we use tx_bit_counter to index
    end

    // Transmit output logic - update miso on negedge
    always_ff @(negedge sclk) begin
        if (cs_n) begin
            miso <= 1'b0;
        end else begin
            if (state == TRANSMIT) begin
                // Transmit MSB first using tx_bit_counter to index
                // tx_bit_counter goes 0->43, we want to send bits 43->0
                miso <= tx_shift_reg[43 - tx_bit_counter];
            end else begin
                miso <= 1'b0;
            end
        end
    end

endmodule