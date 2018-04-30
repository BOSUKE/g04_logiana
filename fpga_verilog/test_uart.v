`timescale 1ns/1ns
module test_uart();

  parameter STEP = 20;  // 20ns周期(=50MHz)
  parameter HALF_STEP = 10;
  parameter SERIAL_1BIT_TIME = 8680; // 1/8680ns = 11520Hz

  reg rst = 1; // 最初はリセット状態
  reg clk = 0;
  wire serial_tx;
  reg serial_rx = 1;

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

  top top (
    .input_clk(clk),
    .rst(rst),
    .serial_rx(serial_rx),
    .serial_tx(serial_tx));

  initial begin // topモジュールから送られてきたデータを受信して表示
    forever begin // 無限ループ
      reg [7:0] data;
      serial_recv_byte(data);
      $display("RECV_DATA = %x", data);
    end
  end

  initial begin // topモジュールにデータを送信する
      #(STEP * 10);     // 10クロック待つ
      rst <= 0;         // リセット解除
      #(STEP * 10);     // 10クロック待つ
      serial_send_byte(8'hAC);
      serial_send_byte(8'hCA);
      serial_send_byte(8'h55);
      serial_send_byte(8'h00);
      serial_send_byte(8'hFF);
      #(STEP * 7000);  // 7000クロック分まつ
      $finish;         // シミュレーション終了
  end

endmodule
