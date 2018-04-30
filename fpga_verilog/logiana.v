// logiana.v
module logiana (
  input clk,
  input rst,
  input [7:0] probe,
  output [7:0] send_data,
  output send_req,
  input send_ready,
  input [7:0] recv_data,
  input recv_valid,
  output [16:0] sram_addr,
  inout [7:0] sram_data,
  output sram_ce_n,
  output sram_oe_n,
  output sram_we_n
);
  // SRAMとの信号線関連のレジスタ
  reg [16:0] sram_write_addr = 0;   // SRAMからのデータをReadする際のアドレス
  reg [16:0] sram_read_addr  = 0;   // SRAMへデータをWriteする際のアドレス
  reg [16:0] sram_addr_reg = 0;     // SRAMに入力するアドレス
  reg sram_oe_n_reg = 1;            // SRAM OE (データ読み出し時に0にする)
  reg sram_we_n_reg = 1;            // SRAM WE (データ書き込み時に0にする)
  reg [7:0] sram_out_reg  = 0;      // SRAMに書き込むデータ
  // SRAM制御信号のassing
  assign sram_addr = sram_addr_reg;
  assign sram_ce_n = 1'b0;
  assign sram_oe_n = sram_oe_n_reg;
  assign sram_we_n = sram_we_n_reg;
  // SRAMデータ線のassing
  wire [7:0] sram_input = sram_data;
  assign sram_data = sram_we_n_reg ? 8'hzz : sram_out_reg;

  // ロジアナ動作設定レジスタ
  reg [7:0] divide_setting = 0;   // サンプリング周波数設定(clkの(X+1)分の1でサンプリング)
  reg [7:0] pos_setting = 0;      // トリガー条件成立後のサンプル数設定
  reg trigger_setting = 0;        // トリガー条件 (1:立ち上がり/0:立下り)
  reg [2:0] probe_setting = 0;    // トリガーとするCHの設定
  // ロジアナ動作の制御レジスタ
  reg running = 0;    // ロジアナ動作中に1とするレジスタ
  reg start_req = 0;  // ロジアナ動作開始を指示する際に1とするレジスタ

  /////////////////////////////////////////////////////////////////////////
  // UARTモジュールが受信したデータの処理(=PCからの設定・指示の処理)
  // PCからのコマンド定義
  parameter DIVIDE_SETTING_CMD = 1,
            POS_SETTING_CMD = 2,
            TRIGER_SETTING_CMD = 3,
            CONTROL_CMD = 4,
            READ_DATA_CMD = 5;
  // trigger_settingの定義
  parameter RISING_TRIGGER = 1,
            FALLING_TRIGER = 0;
  // PCから受信したコマンドの切り分け
  wire [2:0] recv_cmd = recv_data[2:0];
  reg  [2:0] recv_cmd_reg = 0;
  wire [4:0] recv_cmd_reserved = recv_data[6:5];
  wire recv_cmd_valid = (recv_cmd_reserved == 0)
                      && (DIVIDE_SETTING_CMD <= recv_cmd)
                      && (recv_cmd <= READ_DATA_CMD);
  wire recv_cmd_is_write = recv_data[7];
  // PCからの設定・指示の処理を行う制御の状態定義
  parameter WAIT_WRITE_CMD_STATE = 0,  // Write系コマンドの受信待ち
            WAIT_WRITE_DATA_STATE = 1; // データの受信待ち
  reg uart_recv_state = WAIT_WRITE_CMD_STATE;

  always @ (posedge clk or posedge rst) begin
    if (rst) begin
      divide_setting <= 0;
      pos_setting <= 0;
      trigger_setting <= 0;
      probe_setting <= 0;
      start_req <= 0;
      recv_cmd_reg <= 0;
      uart_recv_state <= WAIT_WRITE_CMD_STATE;
    end else begin
      case (uart_recv_state)
        WAIT_WRITE_CMD_STATE: begin
          if (recv_valid && recv_cmd_valid && recv_cmd_is_write) begin
            recv_cmd_reg <= recv_cmd;
            uart_recv_state <= WAIT_WRITE_DATA_STATE;
          end
          start_req <= 0;
        end
        WAIT_WRITE_DATA_STATE: begin
          if (recv_valid) begin
            case (recv_cmd_reg)
              DIVIDE_SETTING_CMD: divide_setting <= recv_data;
              POS_SETTING_CMD: pos_setting <= recv_data;
              TRIGER_SETTING_CMD: begin
                trigger_setting <= recv_data[7];
                probe_setting <= recv_data[2:0];
              end
              CONTROL_CMD:  start_req <= 1;
            endcase
            uart_recv_state <= WAIT_WRITE_CMD_STATE;
          end
        end
      endcase
    end
  end
  /////////////////////////////////////////////////////////////////////////
  // UARTモジュールに対して送信を行う制御
  /////////////////////////////////////////////////////////////////////////
  // UARTモジュールへの入力信号
  reg [7:0] send_reg_data = 0;
  assign send_data = send_reg_data;
  reg send_req_reg = 0;
  assign send_req = send_req_reg;
  // UARTモジュールへの送信制御の状態定義
  parameter WAIT_READ_CMD_STATE = 0,    // Read系コマンド受信待ち
            WAIT_SEND_READY_STATE = 1,  // UART送信可能待ち
            REQ_SRAM_READ_STATE = 2,    // SRAMからのReadを指示する状態
            WAIT_SRAM_READ_STATE = 3,   // SRAMからのデータを待っている状態
            WAIT_SRAM_SEND_READY_STATE = 4; // UART送信可能待ち
  reg [2:0] uart_send_state = WAIT_READ_CMD_STATE;

  always @ (posedge clk or posedge rst) begin
    if (rst) begin
      send_reg_data <= 0;
      send_req_reg <= 0;
      uart_send_state <= WAIT_READ_CMD_STATE;
    end else begin
      case (uart_send_state)
        WAIT_READ_CMD_STATE: begin
          if (recv_valid && recv_cmd_valid && (~recv_cmd_is_write)) begin
            case (recv_cmd)
              DIVIDE_SETTING_CMD: begin
                send_reg_data <= divide_setting;
                uart_send_state <= WAIT_SEND_READY_STATE;
              end
              POS_SETTING_CMD: begin
                send_reg_data <= pos_setting;
                uart_send_state <= WAIT_SEND_READY_STATE;
              end
              TRIGER_SETTING_CMD: begin
                send_reg_data <= {trigger_setting, 4'h00, probe_setting};
                uart_send_state <= WAIT_SEND_READY_STATE;
              end
              CONTROL_CMD: begin
                send_reg_data <= {7'h00, running};
                uart_send_state <= WAIT_SEND_READY_STATE;
              end
              READ_DATA_CMD: begin
                sram_read_addr <= sram_write_addr;
                uart_send_state <= REQ_SRAM_READ_STATE;
              end
            endcase
          end
          send_req_reg <= 0;
        end
        WAIT_SEND_READY_STATE: begin
          if (send_ready) begin
            send_req_reg <= 1;
            uart_send_state <= WAIT_READ_CMD_STATE;
          end
        end
        REQ_SRAM_READ_STATE: begin
          uart_send_state <= WAIT_SRAM_READ_STATE;
          send_req_reg <= 0;
        end
        WAIT_SRAM_READ_STATE: begin
          send_reg_data <= sram_input;
          sram_read_addr <= sram_read_addr + 1'b1;
          uart_send_state <= WAIT_SRAM_SEND_READY_STATE;
          send_req_reg <= 0;
        end
        WAIT_SRAM_SEND_READY_STATE: begin
          if (send_ready) begin
            send_req_reg <= 1;
            if (sram_read_addr == sram_write_addr) begin
              uart_send_state <= WAIT_READ_CMD_STATE;
            end else begin
              uart_send_state <= REQ_SRAM_READ_STATE;
            end
          end
        end
      endcase
    end
  end
  /////////////////////////////////////////////////////////////////////////
  // データのサンプリングとSRAM制御
  /////////////////////////////////////////////////////////////////////////
  // サンプリングするタイミングの生成
  reg [7:0] divide_counter = 0;
  wire sample_point = (divide_counter == 0); //clk立ち上がり時に1ならばサンプリングする
  always @ (posedge clk or posedge rst) begin
    if (rst) begin
      divide_counter <= 0;
    end else begin
      if (divide_counter == divide_setting) begin
        divide_counter <= 0;
      end else begin
        divide_counter <= divide_counter + 1'b1;
      end
    end
  end
  // サンプリング
  reg [7:0] probe_reg = 0;  // サンプリングした値
  always @(posedge clk) begin
    if (sample_point) begin
      probe_reg <= probe;
    end
  end
  // トリガー判定
  wire trigger_probe = probe_reg[probe_setting];
  reg prev_trigger_probe = 0;
  always @(posedge clk) begin
    if (sample_point) begin
      prev_trigger_probe <= trigger_probe;
    end
  end
  wire probe_rising = trigger_probe & (~prev_trigger_probe);
  wire probe_failing = (~trigger_probe) & prev_trigger_probe;
  wire trigger_condition = (trigger_setting == RISING_TRIGGER) ? probe_rising : probe_failing;
  // サンプリング制御とSRAM制御
  reg triggered  = 0; // 一旦、トリガー条件成立すると1
  reg [16:0] sample_counter = 0; // 0x1FFFFまで来たらサンプリング停止
    always @(posedge clk or posedge rst) begin
    if (rst) begin
      running <= 0;
      triggered <= 0;
      sample_counter <= 0;
      sram_addr_reg <= 0;
      sram_out_reg <= 0;
      sram_oe_n_reg <= 1;
      sram_we_n_reg <= 1;
    end else begin
      if (start_req) begin
        running <= 1;
        triggered <= 0;
        sram_write_addr <= 0;
        sram_oe_n_reg <= 1;
        sram_we_n_reg <= 1;
      end else if (running && sample_point) begin
        sram_out_reg <= probe_reg;
        sram_addr_reg <= sram_write_addr;
        sram_write_addr <= sram_write_addr + 1'b1;
        sram_oe_n_reg <= 1;
        if (~triggered) begin
          triggered <= trigger_condition;
          if (trigger_condition) begin
            sample_counter <= {pos_setting, 9'h000};
          end
          sram_we_n_reg <= 0;
        end else begin
          if (sample_counter == 17'h1FFFF) begin
            running <= 0;
            sram_we_n_reg <= 1;
          end else begin
            sample_counter <= sample_counter + 1'b1;
            sram_we_n_reg <= 0;
          end
        end
      end else if (uart_send_state == REQ_SRAM_READ_STATE) begin
        sram_addr_reg <= sram_read_addr;
        sram_oe_n_reg <= 0;
        sram_we_n_reg <= 1;
      end else begin
        sram_oe_n_reg <= 1;
        sram_we_n_reg <= 1;
      end
    end
  end
endmodule
