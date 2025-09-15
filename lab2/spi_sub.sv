module spi_sub (
  input  logic        sclk,
  input  logic        cs_n,
  input  logic        mosi,
  output logic        miso,
  output logic        r_en,
  output logic        w_en,
  output logic [9:0]  addr,
  output logic [31:0] data_o,
  input  logic [31:0] data_i
);

  typedef enum logic [1:0] { IDLE=2'b00, RECEIVE=2'b01, MEMORY=2'b10, TRANSMIT=2'b11 } state_t;
  state_t state, next_state;

  // -------------------- RX (main -> sub) --------------------
  logic [43:0] rx_shift;     // accumulates incoming bits, MSB-first
  logic [5:0]  rx_cnt;       // 0..43
  logic        rx_done;      // strobes when 44th bit captured this posedge

  // -------------------- Latched message fields --------------------
  logic [43:0] msg;          // final 44b message (op[43:42], addr[41:32], data[31:0])
  logic [1:0]  op_reg;
  logic [9:0]  addr_reg;
  logic [31:0] data_reg;

  assign addr   = addr_reg;  // tb_top wires lower bits as needed
  assign data_o = data_reg;

  // -------------------- One-cycle memory access pulse --------------------
  logic mem_pulse;           // 1 exactly on the posedge AFTER 44th bit is sampled
  logic r_en_q, w_en_q;
  assign r_en = r_en_q;
  assign w_en = w_en_q;

  // -------------------- TX (sub -> main) --------------------
  logic [43:0] tx_shift;     // what we will send back
  logic [5:0]  tx_cnt;       // 0..43
  logic        tx_arm;       // true during the half-cycle between memory posedge and next posedge

  // ---------- State register ----------
  always_ff @(posedge sclk) begin
    if (cs_n) state <= IDLE;
    else      state <= next_state;
  end

  // ---------- Next-state logic ----------
  always_comb begin
    next_state = state;
    unique case (state)
      IDLE:     if (!cs_n)      next_state = RECEIVE;
      RECEIVE:  if (rx_done)    next_state = MEMORY;     // finished 44-bit receive
      MEMORY:                   next_state = TRANSMIT;   // one cycle access
      TRANSMIT: if (tx_cnt==43) next_state = IDLE;
      default:                  next_state = IDLE;
    endcase
  end

  // ---------- Receive 44 bits (sample on posedge, MSB first) ----------
  always_ff @(posedge sclk) begin
    if (cs_n) begin
      rx_shift  <= '0;
      rx_cnt    <= '0;
      rx_done   <= 1'b0;
      msg       <= '0;
      op_reg    <= 2'b00;
      addr_reg  <= '0;
      data_reg  <= '0;
      mem_pulse <= 1'b0;
    end else begin
      // Default values
      rx_done <= 1'b0;

      if (state == RECEIVE) begin
        // shift in current bit (MSB first)
        rx_shift <= {rx_shift[42:0], mosi};

        if (rx_cnt < 6'd43) begin
          rx_cnt <= rx_cnt + 1'b1;
        end else begin
          // This is the 44th bit; assemble the *complete* message using previous 43 + current bit.
          logic [43:0] full_msg = {rx_shift[42:0], mosi};
          msg       <= full_msg;
          op_reg    <= full_msg[43:42];
          addr_reg  <= full_msg[41:32];
          data_reg  <= full_msg[31:0];

          rx_done   <= 1'b1;      // tells next-state logic to go to MEMORY
          rx_cnt    <= '0;        // reset for future transactions
        end
      end

      // mem_pulse is the *delayed* (next-cycle) version of rx_done
      mem_pulse <= rx_done;
    end
  end

  // ---------- One-cycle, registered enables on mem_pulse (posedge) ----------
  always_ff @(posedge sclk) begin
    if (cs_n) begin
      r_en_q <= 1'b0;
      w_en_q <= 1'b0;
    end else begin
      r_en_q <= mem_pulse && (op_reg == 2'b00);  // READ
      w_en_q <= mem_pulse && (op_reg == 2'b01);  // WRITE
    end
  end

  // ---------- Prepare TX and arm for immediate negedge output ----------
  logic prev_mem_pulse;  // to detect rising edge of mem_pulse

  always_ff @(posedge sclk) begin
    if (cs_n) begin
      tx_shift <= '0;
      tx_arm   <= 1'b0;
      tx_cnt   <= '0;
      prev_mem_pulse <= 1'b0;
    end else begin
      prev_mem_pulse <= mem_pulse;

      if (mem_pulse) begin
        // For READ: response = op+addr + data_i (RAM is comb on r_en in this lab)
        // For WRITE: response = echo of original message
        tx_shift <= (op_reg == 2'b00) ? {msg[43:32], data_i} : msg;
        tx_arm   <= 1'b1;      // arm for the immediate next negedge
        tx_cnt   <= '0;        // CRITICAL: reset bit index for new transmission
      end else if (state == TRANSMIT) begin
        tx_arm <= 1'b0;        // clear arm once in TRANSMIT state
        // Increment counter for each bit being transmitted
        if (tx_cnt < 6'd43) begin
          tx_cnt <= tx_cnt + 1'b1;
        end
      end else if (state == MEMORY && prev_mem_pulse) begin
        // Special case: increment after first bit sent during armed half-cycle
        if (tx_cnt == 0) begin
          tx_cnt <= 1'b1;
        end
      end
    end
  end

  // ---------- Drive MISO on negedge ----------
  always_ff @(negedge sclk) begin
    if (cs_n) begin
      miso <= 1'b0;
    end else if (tx_arm || state == TRANSMIT) begin
      miso <= tx_shift[43 - tx_cnt];   // MSB first
    end else begin
      miso <= 1'b0;
    end
  end

endmodule