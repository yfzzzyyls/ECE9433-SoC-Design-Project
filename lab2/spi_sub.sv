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

  // Continuous assignments
  assign addr = addr_reg;
  assign data_o = data_reg;
  // Memory enables must be combinational for one-cycle access
  assign r_en = (state == MEMORY) && (op_code == 2'b00);
  assign w_en = (state == MEMORY) && (op_code == 2'b01);

  // Combinational TX data selection
  always_comb begin
    if (op_code == 2'b00 && state == MEMORY) begin
      // For reads during MEMORY state, use current data_i from RAM
      tx_data = {op_code, addr_reg, data_i};
    end else begin
      // For writes and during TRANSMIT state, use registered value
      tx_data = tx_data_write;
    end
  end

  // State machine
  always_ff @(posedge sclk) begin
    if (cs_n) begin
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
    if (cs_n) begin
      // Reset everything
      shift_reg <= '0;
      bit_count <= '0;
      op_code <= '0;
      addr_reg <= '0;
      data_reg <= '0;
      tx_data_write <= '0;
    end else begin

      case (state)
        IDLE: begin
          if (!cs_n && next_state == RECEIVE) begin
            // Capture first bit only when actually transitioning to RECEIVE
            shift_reg <= {43'b0, mosi};
            bit_count <= 6'd1;
          end else begin
            bit_count <= '0;
            shift_reg <= '0;
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
              logic [43:0] complete_msg;
              complete_msg = {shift_reg[42:0], mosi};
              op_code <= complete_msg[43:42];
              addr_reg <= complete_msg[41:32];
              data_reg <= complete_msg[31:0];
            end
          end
        end

        MEMORY: begin
          // Memory access for ONE CYCLE as per spec
          // r_en and w_en are now combinational (see assign statements)
          if (op_code == 2'b00) begin
            // For reads, capture data_i into tx_data_write
            tx_data_write <= {op_code, addr_reg, data_i};
          end else if (op_code == 2'b01) begin
            // For writes, register the echo data
            tx_data_write <= {op_code, addr_reg, data_reg};
          end
          bit_count <= 6'd1; // Will output first bit on negedge, then increment
        end

        TRANSMIT: begin
          // Continue transmission (first bit was output in MEMORY state)
          // NO memory enables during transmit - spec says ONE cycle only
          if (bit_count < 6'd44) begin
            bit_count <= bit_count + 6'd1;
          end
        end
      endcase
    end
  end

  // MISO output logic
  always_ff @(negedge sclk) begin
    if (cs_n) begin
      miso <= 1'b0;
    end
    // Start feedback on the FOLLOWING negedge after MEMORY pulse (per Figure 5)
    // At this negedge, state has transitioned to TRANSMIT and bit_count is 1
    else if (state == TRANSMIT && bit_count == 1) begin
      miso <= tx_data[43];  // First bit (MSB) exactly one half-cycle after the memory pulse
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