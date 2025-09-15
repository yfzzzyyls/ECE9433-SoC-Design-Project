
module spi_sub (
  input  logic        sclk,
  input  logic        cs_n,     // active-low chip select (synchronous reset when high)
  input  logic        mosi,
  output logic        miso,

  // Memory interface
  output logic        r_en,
  output logic        w_en,
  output logic [9:0]  addr,
  output logic [31:0] data_o,
  input  logic [31:0] data_i
);

  // State machine
  typedef enum logic [1:0] {
    IDLE     = 2'b00,
    RECEIVE  = 2'b01,
    MEMORY   = 2'b10,
    TRANSMIT = 2'b11
  } state_t;

  state_t state, next_state;

  // RX signals
  logic [43:0] rx_shift_reg;
  logic [5:0]  rx_bit_count;
  logic        rx_complete;

  // Message storage
  logic [43:0] message;
  logic [1:0]  op_code;
  logic [9:0]  addr_internal;
  logic [31:0] data_internal;

  // TX signals
  logic [43:0] tx_shift_reg;
  logic [43:0] tx_data;       // Combinational TX data preparation
  logic [5:0]  tx_bit_count;
  logic        tx_armed;      // Flag to start TX on next negedge

  // Memory control
  logic mem_access_en;

  // Continuous assignments
  assign addr = addr_internal;
  assign data_o = data_internal;

  // Combinational memory enables for immediate response
  assign r_en = (state == MEMORY) && (op_code == 2'b00);
  assign w_en = (state == MEMORY) && (op_code == 2'b01);

  // State machine - sequential
  always_ff @(posedge sclk) begin
    if (cs_n) begin
      state <= IDLE;
    end else begin
      state <= next_state;
    end
  end

  // State machine - combinational
  always_comb begin
    next_state = state;
    case (state)
      IDLE: begin
        if (!cs_n) next_state = RECEIVE;
      end

      RECEIVE: begin
        if (rx_complete) next_state = MEMORY;
      end

      MEMORY: begin
        next_state = TRANSMIT;
      end

      TRANSMIT: begin
        if (tx_bit_count == 6'd43) next_state = IDLE;
      end

      default: next_state = IDLE;
    endcase
  end

  // RX logic - sample on posedge
  always_ff @(posedge sclk) begin
    if (cs_n) begin
      rx_shift_reg <= '0;
      rx_bit_count <= '0;
      rx_complete <= 1'b0;
      message <= '0;
      op_code <= '0;
      addr_internal <= '0;
      data_internal <= '0;
    end else begin
      rx_complete <= 1'b0;

      if (next_state == RECEIVE || state == RECEIVE) begin
        // Shift in new bit (MSB first)
        // Sample when entering or in RECEIVE state
        rx_shift_reg <= {rx_shift_reg[42:0], mosi};

        if (rx_bit_count == 6'd43) begin
          // Complete 44-bit message received
          logic [43:0] complete_msg;
          complete_msg = {rx_shift_reg[42:0], mosi};

          rx_complete <= 1'b1;
          message <= complete_msg;
          op_code <= complete_msg[43:42];      // Extract from complete message
          addr_internal <= complete_msg[41:32]; // Extract from complete message
          data_internal <= complete_msg[31:0];  // Extract from complete message
          rx_bit_count <= '0;
        end else begin
          rx_bit_count <= rx_bit_count + 1'b1;
        end
      end
    end
  end

  // Memory access control
  always_ff @(posedge sclk) begin
    if (cs_n) begin
      mem_access_en <= 1'b0;
    end else begin
      mem_access_en <= (state == MEMORY);
    end
  end


  // Combinational TX data preparation
  always_comb begin
    if (op_code == 2'b00) begin
      // READ: return op+addr from message, data from RAM
      tx_data = {message[43:32], data_i};
    end else begin
      // WRITE: echo entire message
      tx_data = message;
    end
  end

  // TX preparation and control
  always_ff @(posedge sclk) begin
    if (cs_n) begin
      tx_shift_reg <= '0;
      tx_bit_count <= '0;
      tx_armed <= 1'b0;
    end else begin
      if (state == MEMORY) begin
        // Load TX shift register during memory cycle
        tx_shift_reg <= tx_data;  // Use combinational tx_data
        tx_bit_count <= 6'd1;  // Start at 1 since bit[43] is output during MEMORY
        tx_armed <= 1'b1;  // ARM: Signal to start TX on very next negedge
      end else if (state == TRANSMIT) begin
        tx_armed <= 1'b0;  // Not really needed anymore but keep for safety
        // Increment for next bit
        if (tx_bit_count < 6'd43) begin
          tx_bit_count <= tx_bit_count + 1'b1;
        end
      end else begin
        tx_armed <= 1'b0;
      end
    end
  end

  // MISO output and bit counter - drive on negedge
  // Need to start outputting during MEMORY state's negedge for correct timing
  always_ff @(negedge sclk) begin
    if (cs_n) begin
      miso <= 1'b0;
    end else if (state == MEMORY) begin
      // During MEMORY state, output first bit (bit 43)
      // tx_bit_count will be 1 on next posedge, but we output bit 43 directly
      miso <= tx_data[43];
    end else if (state == TRANSMIT) begin
      // During TRANSMIT state, continue outputting bits
      // tx_bit_count has been incremented on posedge
      miso <= tx_shift_reg[43 - tx_bit_count];
    end else begin
      miso <= 1'b0;
    end
  end

endmodule