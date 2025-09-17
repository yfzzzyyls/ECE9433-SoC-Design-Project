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
  logic [43:0] shift_reg;     // For receiving data
  logic [43:0] tx_reg;         // For transmitting data
  logic [5:0]  bit_count;      // Count bits (0-43)

  // Extracted fields
  logic [1:0]  op_code;
  logic [9:0]  addr_reg;
  logic [31:0] data_reg;

  // State machine - posedge
  always_ff @(posedge sclk) begin
    if (cs_n) begin
      state <= IDLE;
    end else begin
      state <= next_state;
    end
  end

  // Next state logic - combinational
  always_comb begin
    next_state = state;
    case (state)
      IDLE: begin
        if (!cs_n) next_state = RECEIVE;
      end
      RECEIVE: begin
        if (bit_count == 6'd43) next_state = MEMORY;
      end
      MEMORY: begin
        next_state = TRANSMIT;
      end
      TRANSMIT: begin
        if (bit_count == 6'd43) next_state = IDLE;
      end
    endcase
  end

  // Main logic - posedge
  always_ff @(posedge sclk) begin
    if (cs_n) begin
      // Reset everything when cs_n is high
      shift_reg <= '0;
      tx_reg <= '0;
      bit_count <= '0;
      op_code <= '0;
      addr_reg <= '0;
      data_reg <= '0;
    end else begin
      case (state)
        IDLE: begin
          if (next_state == RECEIVE) begin
            // Starting new reception - reset for fresh start
            shift_reg <= '0;
            bit_count <= 6'd0;
          end
        end

        RECEIVE: begin
          if (bit_count < 6'd44) begin
            // Shift in new bit
            shift_reg <= {shift_reg[42:0], mosi};
            bit_count <= bit_count + 6'd1;

            // Extract fields when we have all 44 bits
            if (bit_count == 6'd43) begin
              // Complete message will be {shift_reg[42:0], mosi}
              // shift_reg has bits [43:1], mosi has bit [0]
              op_code <= shift_reg[42:41];
              addr_reg <= shift_reg[40:31];
              data_reg <= {shift_reg[30:0], mosi};
            end
          end
        end

        MEMORY: begin
          // Prepare TX data based on operation
          if (op_code == 2'b00) begin
            // Read: return op, addr, and data from memory
            tx_reg <= {op_code, addr_reg, data_i};
          end else begin
            // Write or other: echo the received message
            tx_reg <= {op_code, addr_reg, data_reg};
          end
          bit_count <= 6'd0;  // Reset for transmission
        end

        TRANSMIT: begin
          if (bit_count < 6'd44) begin
            bit_count <= bit_count + 6'd1;
          end
        end
      endcase
    end
  end

  // Memory control signals - combinational
  assign r_en = (state == MEMORY) && (op_code == 2'b00);
  assign w_en = (state == MEMORY) && (op_code == 2'b01);
  assign addr = addr_reg;
  assign data_o = data_reg;

  // MISO output - negedge
  always_ff @(negedge sclk) begin
    if (cs_n) begin
      miso <= 1'b0;
    end else if (state == TRANSMIT) begin
      // Output bits MSB first
      miso <= tx_reg[43 - bit_count];
    end else begin
      // During receive or idle, keep miso low
      miso <= 1'b0;
    end
  end

endmodule