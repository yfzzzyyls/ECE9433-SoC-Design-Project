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

  // ===== 状态与寄存器 =====
  typedef enum logic [1:0] {IDLE, RECV, ACCESS, RESP} state_e;
  state_e      state;

  logic [43:0] rx_shift, tx_shift;
  logic  [5:0] rx_cnt,   tx_cnt;

  logic        arm_resp;                      // posedge：ACCESS 时置 1，RESP 下个 posedge 清 0
  logic        resp_active;                   // negedge：回传进行中

  // 仅在 negedge 块写的内部寄存器；端口用连续赋值驱动
  logic        miso_q;
  assign miso = miso_q;

  // 回传结束跨沿握手：negedge 翻转 resp_tog；posedge 采样 resp_tog_q
  logic resp_tog;    // negedge 写（toggle）
  logic resp_tog_q;  // posedge 采样（与 resp_tog 不同即收到事件）

  // ==================== 接收 + 访问内存（posedge） ====================
  always_ff @(posedge sclk) begin
    // 默认 1 拍脉冲
    r_en <= 1'b0;
    w_en <= 1'b0;

    if (cs_n) begin
      // 复位：只清本域寄存器；采样端保存 toggle 基线
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
          // 首位在主机上一个 negedge 已经放好——本 posedge 立刻采样
          state    <= RECV;
          rx_cnt   <= 6'd0;
          rx_shift <= {rx_shift[42:0], mosi};
        end

        RECV: begin
          rx_shift <= {rx_shift[42:0], mosi};
          // 因为 IDLE 已经采了首位，这里只需再采 43-1 = 42 次：计数 0..42
          if (rx_cnt == 6'd42) begin
            state  <= ACCESS;
            rx_cnt <= 6'd0;
          end else begin
            rx_cnt <= rx_cnt + 6'd1;
          end
        end

        ACCESS: begin
          // 访存恰好 1 个 posedge 周期
          addr <= rx_shift[41:32];
          if (rx_shift[43:42] == 2'b00) begin
            r_en <= 1'b1;                     // 读：这拍 data_i 有效
          end else begin
            w_en   <= 1'b1;                   // 写：这拍写入 data_o
            data_o <= rx_shift[31:0];
          end
          arm_resp <= 1'b1;                   // 下一次 negedge 启动回传
          state    <= RESP;
        end

        RESP: begin
          if (arm_resp) arm_resp <= 1'b0;     // 只装载一次，防重复

          // 背靠背多帧：收到“回传结束”事件后（仍然 cs_n=0）
          // 先回到 IDLE，不在本拍采样；等下一次 posedge 由 IDLE 采首位
          if ((resp_tog ^ resp_tog_q) && !cs_n) begin
            resp_tog_q <= resp_tog;           // 吃掉事件
            state      <= IDLE;
          end
        end
      endcase
    end
  end

  // ==================== 回应（negedge） ====================
  always_ff @(negedge sclk) begin
    // 块首声明临时变量（工具更兼容）
    logic [1:0]  op_l;
    logic [9:0]  ad_l;
    logic [31:0] da_l;

    if (cs_n) begin
      miso_q      <= 1'b0;
      tx_shift    <= '0;
      tx_cnt      <= 6'd0;
      resp_active <= 1'b0;
      resp_tog    <= 1'b0;                   // reset toggle
    end
    else if (state == RESP) begin
      if (!resp_active) begin
        if (arm_resp) begin
          // 第一次 negedge：装载响应帧，并推出 MSB
          op_l = rx_shift[43:42];
          ad_l = rx_shift[41:32];
          da_l = (op_l == 2'b00) ? data_i : rx_shift[31:0];
          tx_shift    <= {op_l, ad_l, da_l};
          miso_q      <= {op_l, ad_l, da_l}[43];  // MSB 先出
          tx_cnt      <= 6'd0;
          resp_active <= 1'b1;
        end else begin
          miso_q <= 1'b0;                    // 接收阶段保持 0（半双工）
        end
      end
      else begin
        // 回传中：每个 negedge 推一位并左移
        miso_q   <= tx_shift[43];
        tx_shift <= {tx_shift[42:0], 1'b0};
        if (tx_cnt == 6'd43) begin
          resp_active <= 1'b0;               // 44 位结束
          tx_cnt      <= 6'd0;
          // 不要在同一拍把 miso_q 清 0，保持最后一位到下个 posedge
          resp_tog    <= ~resp_tog;          // 产生“回传结束”事件（toggle）
        end else begin
          tx_cnt <= tx_cnt + 6'd1;
        end
      end
    end
    else begin
      miso_q <= 1'b0;                         // 非 RESP 阶段拉低
    end
  end

endmodule
