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

  // Combinational TX data selection
  always_comb begin
    if (op_code == 2'b00 && (state == MEMORY || state == TRANSMIT)) begin
      // For reads, use current data_i from RAM
      tx_data = {op_code, addr_reg, data_i};
    end else begin
      // For writes, use registered value
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
        if (bit_count == 6'd44) next_state = MEMORY;
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
      r_en <= 1'b0;
      w_en <= 1'b0;
    end else begin
      // Default values
      r_en <= 1'b0;
      w_en <= 1'b0;

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

          end

          if (bit_count == 6'd44) begin
            // Extract fields from complete message
            op_code <= shift_reg[43:42];
            addr_reg <= shift_reg[41:32];
            data_reg <= shift_reg[31:0];
          end
        end

        MEMORY: begin
          // Memory access and TX data preparation
          if (op_code == 2'b00) begin
            r_en <= 1'b1;
            // For reads, tx_data is handled combinationally
          end else if (op_code == 2'b01) begin
            w_en <= 1'b1;
            // For writes, register the echo data
            tx_data_write <= {op_code, addr_reg, data_reg};
          end
          bit_count <= 6'd2; // Compensate for 1-bit shift
        end

        TRANSMIT: begin
          // Continue transmission (first bit was output in MEMORY state)
          if (op_code == 2'b00) begin
            // For reads, keep r_en high to maintain data_i from combinational RAM
            r_en <= 1'b1;
          end
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
    end else if ((state == MEMORY && next_state == TRANSMIT) ||
                 (state == TRANSMIT && bit_count >= 2 && bit_count <= 44)) begin
      // Start outputting on the negedge after memory access
      if (state == MEMORY) begin
        miso <= tx_data[43]; // First bit (MSB)
      end else begin
        // In TRANSMIT state, continue outputting remaining bits
        // bit_count=2 outputs bit 42, bit_count=44 outputs bit 0
        miso <= tx_data[44 - bit_count];
      end
    end else begin
      miso <= 1'b0;
    end
  end

endmodule