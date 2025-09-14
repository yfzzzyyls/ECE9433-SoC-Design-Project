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

    // Decode operation type
    assign is_read_op  = (message_buffer[43:42] == 2'b00);
    assign is_write_op = (message_buffer[43:42] == 2'b01);

    // Message complete when we've received 44 bits
    assign message_complete = (state == RECEIVE) && (bit_counter == 6'd43);

    // Memory interface signals
    assign addr = message_buffer[41:32];
    assign data_o = message_buffer[31:0];

    // Memory control - pulse for one cycle in MEMORY state
    always_ff @(posedge sclk) begin
        if (cs_n) begin
            r_en <= 1'b0;
            w_en <= 1'b0;
        end else begin
            // Assert r_en or w_en only in MEMORY state
            r_en <= (state == MEMORY) && is_read_op;
            w_en <= (state == MEMORY) && is_write_op;
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
        end else begin
            if (state == RECEIVE) begin
                // Shift in MOSI bit (MSB first)
                rx_shift_reg <= {rx_shift_reg[42:0], mosi};
                bit_counter <= bit_counter + 1'b1;

                // Store complete message
                if (bit_counter == 6'd43) begin
                    message_buffer <= {rx_shift_reg[42:0], mosi};
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

    // Prepare transmit data - only on posedge
    always_ff @(posedge sclk) begin
        if (cs_n) begin
            tx_shift_reg <= 44'b0;
        end else if (state == MEMORY) begin
            // Load transmit register during MEMORY state
            if (is_read_op) begin
                // For read: return opcode, address, and data from RAM
                tx_shift_reg <= {message_buffer[43:32], data_i};
            end else begin
                // For write: echo the complete message
                tx_shift_reg <= message_buffer;
            end
        end
        // Note: tx_shift_reg doesn't shift - we use bit_counter to index
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