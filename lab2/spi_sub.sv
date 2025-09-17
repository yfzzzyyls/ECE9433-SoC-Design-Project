module spi_sub (
  input  logic        sclk,
  input  logic        cs_n,
  input  logic        mosi,
  output logic        miso,

  // Memory interface
  output logic        r_en,
  output logic        w_en,
  output logic [9:0]  addr,
  output logic [31:0] data_o,
  input  logic [31:0] data_i
);

  // FSM states
  typedef enum logic [1:0] {
    IDLE     = 2'b00,
    RECEIVE  = 2'b01,
    MEMORY   = 2'b10,
    TRANSMIT = 2'b11
  } state_t;

  state_t state, next_state;

  // Internal registers
  logic [43:0] shift_reg;
  logic [5:0]  bit_count;
  logic [1:0]  op_code;
  logic [9:0]  addr_reg;
  logic [31:0] data_reg;
  logic [43:0] tx_data;
  logic [43:0] tx_data_write;
  logic        async_clear;  // Flag for negedge->posedge reset
  logic        in_main_msg;  // Track when Main is sending
  logic [43:0] current_msg;  // Complete message assembly
  logic [43:0] complete_message; // Captured complete message

  // Continuous assignments
  assign current_msg = {shift_reg[42:0], mosi};
  // During MEMORY state, use captured complete message; otherwise use registered values
  assign addr = (state == MEMORY) ? complete_message[41:32] : addr_reg;
  assign data_o = (state == MEMORY) ? complete_message[31:0] : data_reg;
  // Memory enables must be combinational for one-cycle access
  // Use the captured complete message to determine operation during MEMORY state
  assign r_en = (state == MEMORY) && (complete_message[43:42] == 2'b00);
  assign w_en = (state == MEMORY) && (complete_message[43:42] == 2'b01);

  // Debug complete_message during MEMORY state (commented out for production)
  // always @(posedge sclk) begin
  //   if (state == MEMORY) begin
  //     $display("DEBUG MEMORY: time=%0t, complete_msg=0x%h, bit_count=%d",
  //              $time, complete_message, bit_count);
  //   end
  //   if (state == RECEIVE && bit_count == 43) begin
  //     $display("DEBUG RECEIVE: Capturing last bit, shift_reg=0x%h, mosi=%b",
  //              shift_reg[42:0], mosi);
  //   end
  // end

  // Combinational TX data selection
  always_comb begin
    if (complete_message[43:42] == 2'b00 && state == MEMORY) begin
      // For reads during MEMORY state, use current data_i from RAM
      tx_data = {complete_message[43:42], complete_message[41:32], data_i};
    end else begin
      // For writes and during TRANSMIT state, use registered value
      tx_data = tx_data_write;
    end
  end

  // State machine
  always_ff @(posedge sclk) begin
    // Fix #1: Honor negedge reset via async_clear flag
    if (cs_n || async_clear) begin
      state <= IDLE;
    end else begin
      state <= next_state;
    end
  end

  // Next state logic
  always_comb begin
    next_state = state;
    case (state)
      IDLE: begin
        if (!cs_n) next_state = RECEIVE;
      end
      RECEIVE: begin
        if (bit_count == 6'd43) next_state = MEMORY;  // Transition when capturing last bit
      end
      MEMORY: begin
        next_state = TRANSMIT;
      end
      TRANSMIT: begin
        if (bit_count == 6'd44) next_state = IDLE;
      end
    endcase
  end

  // Main sequential logic
  always_ff @(posedge sclk) begin
    // Fix #1: Include async_clear in reset condition
    if (cs_n || async_clear) begin
      // Reset everything
      shift_reg <= '0;
      bit_count <= '0;
      op_code <= '0;
      addr_reg <= '0;
      data_reg <= '0;
      tx_data_write <= '0;
      in_main_msg <= 1'b0;
    end else begin

      case (state)
        IDLE: begin
          if (!cs_n) begin
            // cs_n is low - prepare for new frame
            // Special handling: if bit_count==44, we just came from TRANSMIT
            // and should wait one cycle before capturing (gap between frames)
            if (bit_count == 6'd44) begin
              // Just finished transmitting, wait for gap
              bit_count <= 6'd0;  // Reset for next frame
              shift_reg <= '0;
              in_main_msg <= 1'b1;
              // Clear registers but don't capture first bit yet
              op_code <= '0;
              addr_reg <= '0;
              data_reg <= '0;
              tx_data_write <= '0;
              complete_message <= '0;
            end else begin
              // Either initial frame or after gap - capture first bit
              shift_reg <= {43'b0, mosi};
              bit_count <= 6'd1;  // Already have first bit
              in_main_msg <= 1'b1;
              // Reset message parsing registers
              op_code <= '0;
              addr_reg <= '0;
              data_reg <= '0;
              tx_data_write <= '0;
              complete_message <= '0;
            end
          end else begin
            // cs_n is high, do full reset
            bit_count <= '0;
            shift_reg <= '0;
            in_main_msg <= 1'b0;
            complete_message <= '0;
          end
        end

        RECEIVE: begin
          if (bit_count < 6'd44) begin
            // Shift in new bit
            shift_reg <= {shift_reg[42:0], mosi};
            bit_count <= bit_count + 6'd1;

            // When we just captured the 44th bit (bit_count was 43, now 44)
            if (bit_count == 6'd43) begin
              // Build complete message including the bit we're capturing now
              complete_message <= {shift_reg[42:0], mosi};
            end
          end
        end

        MEMORY: begin
          // Use the captured complete message
          op_code <= complete_message[43:42];
          addr_reg <= complete_message[41:32];
          data_reg <= complete_message[31:0];

          if (complete_message[43:42] == 2'b00) begin
            // For reads, capture data_i into tx_data_write
            tx_data_write <= {complete_message[43:42], complete_message[41:32], data_i};
          end else if (complete_message[43:42] == 2'b01) begin
            // For writes, register the echo data
            tx_data_write <= complete_message;
          end
          bit_count <= 6'd1; // Will output first bit on negedge, then increment
          in_main_msg <= 1'b0;  // Fix #3: About to start Sub response
        end

        TRANSMIT: begin
          if (bit_count < 6'd44) begin
            bit_count <= bit_count + 6'd1;
          end
          // When we reach 44, we'll transition to IDLE on next cycle
          // IDLE will handle the reset
        end
      endcase
    end
  end

  // Negedge logic for async_clear flag
  always_ff @(negedge sclk) begin
    if (cs_n) begin
      async_clear <= 1'b1;  // Fix #1: Set flag for posedge reset
    end else begin
      async_clear <= 1'b0;
    end
  end

  // MISO output logic
  always_ff @(negedge sclk) begin
    if (cs_n) begin
      miso <= 1'b0;
    end
    // Fix #3: Guarantee miso=0 during Main's message
    else if (in_main_msg) begin
      miso <= 1'b0;  // Hard-clamp during Main's frame
    end
    // Start TX on the following negedge after memory pulse
    // At this negedge, state is MEMORY but bit_count was just set to 1
    else if (state == MEMORY && bit_count == 1) begin
      miso <= tx_data[43];  // First bit (MSB) on following negedge
    end
    else if (state == TRANSMIT && bit_count >= 2 && bit_count <= 44) begin
      // bit_count=2 outputs bit 42, bit_count=3 outputs bit 41, etc.
      miso <= tx_data[44 - bit_count];
    end
    else begin
      miso <= 1'b0;
    end
  end

endmodule