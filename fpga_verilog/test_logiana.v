`timescale 1ns/1ns
module test_logiana();

  reg clk = 0;
  reg rst = 0;
  reg serial_rx = 1;
  wire serial_tx;
  reg [7:0] probe = 0;
  wire [16:0] sram_addr;
  wire [7:0] sram_data;
  wire sram_ce_n;
  wire sram_oe_n;
  wire sram_we_n;

  parameter STEP = 20;  // 20ns周期(=50MHz)
  parameter HALF_STEP = 10;
  parameter SERIAL_1BIT_TIME = 8680; // 1/8680ns = 11520Hz

  always #(HALF_STEP) begin // 50MHzで変化するclkの生成
    clk <= ~clk;
  end
  task send_bit; // 1bitデータをserial_rxに送り込む
    input data;
    begin
      serial_rx <= data;
      #(SERIAL_1BIT_TIME);
    end
  endtask
  task serial_send_byte; // 1byteデータをserial_rxに送り込む
    input [7:0] data;
    begin
      integer i;
      send_bit(0);
      for (i = 0; i < 8; i = i + 1) begin
        send_bit(data[i]);
      end
      send_bit(1);
    end
  endtask
  task serial_recv_byte; // serial_txからのデータ受信
    output [7:0] data;
    begin
      integer i;
      wait(serial_tx == 0); //　Start Bit待ち
      #(SERIAL_1BIT_TIME);
      #(SERIAL_1BIT_TIME / 2); // 値を確認するポイントを1/2周期ずらす
      for (i = 0; i < 8; i = i + 1) begin
        data[i] <= serial_tx;
        #(SERIAL_1BIT_TIME);
      end
      #(SERIAL_1BIT_TIME); // Stop Bit
    end
  endtask

  // SRAMモデル
  async_128Kx8 sram(
    .CE_b(sram_ce_n),
    .WE_b(sram_we_n),
    .OE_b(sram_oe_n),
    .A(sram_addr),
    .DQ(sram_data));
  
  // 簡易ロジアナのTOPモジュール
  top top(
    .input_clk(clk),
    .rst(rst),
    .serial_rx(serial_rx),
    .serial_tx(serial_tx),
    .probe(probe),
    .sram_addr(sram_addr),
    .sram_data(sram_data),
    .sram_ce_n(sram_ce_n),
    .sram_oe_n(sram_oe_n),
    .sram_we_n(sram_we_n));

  initial begin
    reg [7:0] data;
    #(STEP * 10); 
    rst <= 0;     
    #(STEP * 10); 

    // 値の設定
    serial_send_byte(8'h81); // DIVIDE_SETTING_CMD
    serial_send_byte(8'h01);
    serial_send_byte(8'h82); // POS_SETTING_CMD
    serial_send_byte(8'hC0);
    serial_send_byte(8'h83); // TRIGER_SETTING_CMD
    serial_send_byte({1'b1, 7'h3}); // Rising CH3

    // 値の読み出し
    serial_send_byte(8'h01); // DIVIDE_SETTING_CMD
    serial_recv_byte(data);
    $display("DIVIDE_SETTING_CMD = %x", data);
    serial_send_byte(8'h02); // POS_SETTING_CMD
    serial_recv_byte(data);
    $display("POS_SETTING_CMD = %x", data);
    serial_send_byte(8'h03); // TRIGER_SETTING_CMD
    serial_recv_byte(data);
    $display("TRIGER_SETTING_CMD = %x", data);
    serial_send_byte(8'h04); // CONTROL_CMD
    serial_recv_byte(data);
    $display("CONTROL_CMD = %x", data);

    // サンプリングスタート
    serial_send_byte(8'h84); // CONTROL_CMD
    serial_send_byte(8'hCC);
    serial_send_byte(8'h04); // CONTROL_CMD
    serial_recv_byte(data);
    $display("CONTROL_CMD = %x", data);

    // 適当にProbeの値を変化させる
    #(STEP * 200000);
    probe[2] = 1;
    #(STEP * 2000);
    probe[3] = 1;   // これでトリガ条件成立
    #(STEP * 30);
    probe[4] = 1;
    #(STEP * 30);
    probe[5] = 1;
    #(STEP * 200000);

    // サンプリング終了確認
    serial_send_byte(8'h04); // CONTROL_CMD
    serial_recv_byte(data);
    $display("CONTROL_CMD = %x", data);

    // データ読み出し
    serial_send_byte(8'h05); // READ_DATA_CMD
    #(STEP * 500000);

    $finish;
  end
endmodule
