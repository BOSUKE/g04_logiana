// uart.v
module uart (
  input wire clk,
  input wire rst,
  input wire rx,
  output wire tx,
  input wire [7:0] send_data,
  input wire send_req,
  output wire send_ready,
  output wire [7:0] recv_data,
  output wire recv_valid
  );

  // (100 MHz) / ((115 200 Hz) * 4) = 217
  parameter CLK_x4_DIV_COUNTER_WIDTH = 8;
  parameter CLK_x4_DIV_COUNT = 216;

  wire baud_x4_clk;
  wire baud_clk;

  reg [CLK_x4_DIV_COUNTER_WIDTH-1:0] div_counter = CLK_x4_DIV_COUNT;
  assign baud_x4_clk = (div_counter == 0);
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      div_counter <= CLK_x4_DIV_COUNT;
    end else begin
      if (div_counter == 0) begin
        div_counter <= CLK_x4_DIV_COUNT;
      end else begin
        div_counter <= div_counter - 1'b1;
      end
    end
  end
  reg [1:0] x4counter = 2'b11;
  assign baud_clk = (x4counter == 0) & baud_x4_clk;
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      x4counter <= 2'b11;
    end else begin
      if (baud_x4_clk) begin
        x4counter <= {x4counter[0], ~x4counter[1]};
      end
    end
  end

  reg tx_reg = 1;
  reg send_ready_reg = 1;
  reg [7:0] tx_data = 0;
  reg [3:0] tx_counter = 0;
  parameter TX_IDLE = 0,       // 送信要求待ち
            TX_START_SEND = 1, // Start Bitの送信をこれから開始する状態
            TX_BIT0_SEND = 2,  // 0Bit目のデータをこれから開始する状態
            TX_BIT7_SEND = 9,  // 7Bii目のデータをこれから開始する状態
            TX_STOP_SEND = 10, // Stop Bitの送信をこれから開始する状態
            TX_STOP_WAIT = 11; // Stop Bitの送信が完了するのを待っている状態

  assign tx = tx_reg;
  assign send_ready = send_ready_reg;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      tx_reg <= 1;
      tx_data <= 0;
      tx_counter <= 0;
      send_ready_reg <= 1;
    end else begin
      case (tx_counter)
        TX_IDLE: begin
          if (send_req) begin
            tx_data <= send_data;
            tx_counter <= tx_counter + 1'b1;
            send_ready_reg <= 0;
          end
        end
        TX_START_SEND: begin
          if (baud_clk) begin
            tx_reg <= 0;
            tx_counter <= tx_counter + 1'b1;
          end
        end
        TX_STOP_SEND: begin
          if (baud_clk) begin
            tx_reg <= 1;
            tx_counter <= tx_counter + 1'b1;
          end
        end
        TX_STOP_WAIT: begin
          if (baud_clk) begin
            tx_counter <= TX_IDLE;
            send_ready_reg <= 1;
          end
        end
        default : begin // TX_BIT0_SEND～TX_BIT7_SEND
          if (baud_clk) begin
            tx_reg <= tx_data[0];
            tx_data <= {1'b0, tx_data[7:1]};
            tx_counter <= tx_counter + 1'b1;
          end
        end
      endcase
    end
  end

  reg [7:0] recv_data_reg = 0;
	reg recv_valid_reg = 0;
	reg [3:0] rx_counter = 0;
	reg [1:0] sample_counter = 0;
	wire sample_point = (sample_counter == 0);
	parameter RX_IDLE = 0,       // Start Bitの0の検出待ち
            RX_START_RECV = 1, // Start Bitの0の受信待ち
	          RX_BIT0_RECV  = 2, // Bit0の受信町
	          RX_BIT7_SEND  = 9, // Bit7の受信町
	          RX_STOP_RECV = 10; // Stop Bitの受信待ち

  assign recv_data = recv_data_reg;
  assign recv_valid = recv_valid_reg;

	always @(posedge clk or posedge rst) begin
		if (rst) begin
			recv_data_reg <= 0;
			recv_valid_reg <= 0;
			rx_counter <= 0;
			sample_counter <= 0;
		end else begin
			case (rx_counter)
				RX_IDLE: begin
					if (baud_x4_clk && (rx == 0)) begin
							rx_counter <= rx_counter + 1'b1;
							sample_counter <= 0;
					end
					recv_valid_reg <= 0;
				end
				RX_START_RECV: begin
					if (baud_x4_clk) begin
						if (sample_point) begin
              if (rx == 0) begin // スタートビットの0確認
                rx_counter <= rx_counter + 1'b1;
              end else begin
                rx_counter <= RX_IDLE;  // 0のはずが0ではない(=通信エラー)
              end
						end
						sample_counter <= sample_counter + 1'b1;
					end
				end
				RX_STOP_RECV: begin
					if (baud_x4_clk) begin
						if (sample_point) begin
              if (rx == 1) begin // ストップビットの1確認
                recv_valid_reg <= 1;
              end
							rx_counter <= RX_IDLE;
						end
						sample_counter <= sample_counter + 1'b1;
					end
				end
				default: begin
					if (baud_x4_clk) begin
						if (sample_point) begin
							recv_data_reg <= {rx, recv_data_reg[7:1]};
							rx_counter <= rx_counter + 1'b1;
						end
						sample_counter <= sample_counter + 1'b1;
					end
				end
			endcase
		end
	end

endmodule
