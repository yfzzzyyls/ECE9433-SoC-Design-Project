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

  typedef enum logic [1:0] {IDLE, RECV, ACCESS, RESP} state_e;
  state_e      state;

  logic [43:0] rx_shift, tx_shift;
  logic  [5:0] rx_cnt,   tx_cnt;

  logic        arm_resp;
  logic        resp_active;

  logic        miso_q;
  assign miso = miso_q;

  logic resp_tog;
  logic resp_tog_q;

  always_ff @(posedge sclk) begin
    r_en <= 1'b0;
    w_en <= 1'b0;

    if (cs_n) begin
      state      <= IDLE;
      rx_shift   <= '0;
      rx_cnt     <= 6'd0;
      arm_resp   <= 1'b0;
      addr       <= '0;
      data_o     <= '0;
      resp_tog_q <= resp_tog;
    end
    else begin
      unique case (state)
        IDLE: begin
          state    <= RECV;
          rx_cnt   <= 6'd0;
          rx_shift <= {rx_shift[42:0], mosi};
        end

        RECV: begin
          rx_shift <= {rx_shift[42:0], mosi};
          if (rx_cnt == 6'd42) begin
            state  <= ACCESS;
            rx_cnt <= 6'd0;
          end else begin
            rx_cnt <= rx_cnt + 6'd1;
          end
        end

        ACCESS: begin
          addr <= rx_shift[41:32];
          if (rx_shift[43:42] == 2'b00) begin
            r_en <= 1'b1;
          end else begin
            w_en   <= 1'b1;
            data_o <= rx_shift[31:0];
          end
          arm_resp <= 1'b1;
          state    <= RESP;
        end

        RESP: begin
          if (arm_resp) arm_resp <= 1'b0;

          if ((resp_tog ^ resp_tog_q) && !cs_n) begin
            resp_tog_q <= resp_tog;
            state      <= IDLE;
          end
        end
      endcase
    end
  end

  always_ff @(negedge sclk) begin
    logic [1:0]  op_l;
    logic [9:0]  ad_l;
    logic [31:0] da_l;

    if (cs_n) begin
      miso_q      <= 1'b0;
      tx_shift    <= '0;
      tx_cnt      <= 6'd0;
      resp_active <= 1'b0;
      resp_tog    <= 1'b0;
    end
    else if (state == RESP) begin
      if (!resp_active) begin
        if (arm_resp) begin
          op_l = rx_shift[43:42];
          ad_l = rx_shift[41:32];
          da_l = (op_l == 2'b00) ? data_i : rx_shift[31:0];
          tx_shift    <= {op_l, ad_l, da_l};
          miso_q      <= {op_l, ad_l, da_l}[43];
          tx_cnt      <= 6'd0;
          resp_active <= 1'b1;
        end else begin
          miso_q <= 1'b0;
        end
      end
      else begin
        miso_q   <= tx_shift[43];
        tx_shift <= {tx_shift[42:0], 1'b0};
        if (tx_cnt == 6'd43) begin
          resp_active <= 1'b0;
          tx_cnt      <= 6'd0;
          resp_tog    <= ~resp_tog;
        end else begin
          tx_cnt <= tx_cnt + 6'd1;
        end
      end
    end
    else begin
      miso_q <= 1'b0;
    end
  end

endmodule
