// top.v
module top (
  input wire input_clk, // 発振器からの入力50Mz
  input wire rst,       // リセット入力
  input wire serial_rx, // USB-シリアル変換チップ -> FPGA
  output wire serial_tx,// USB-シリアル変換チップ <- FPGA
  input [7:0] probe,    // サンプリング対象信号8bit(8ch)
	output [16:0] sram_addr, // -> SRAM
  inout [7:0] sram_data,   // <-> SRAM
  output sram_ce_n,        // -> SRAM
  output sram_oe_n,        // -> SRAM
  output sram_we_n         // -> SRAM
  );

  wire clk; // 100MHzクロック
	wire [7:0] send_data;
	wire send_ready;
	wire send_req;
	wire [7:0] recv_data;
	wire recv_valid;

  pll pll(.CLKI(input_clk), .CLKOP(clk));

  uart uart(
    .clk(clk),
    .rst(rst),
    .rx(serial_rx),
    .tx(serial_tx),
    .send_data(send_data),
    .send_req(send_req),
    .send_ready(send_ready),
    .recv_data(recv_data),
    .recv_valid(recv_valid));
	logiana logiana(
		.clk(clk),
		.rst(rst),
		.probe(probe),
		.send_data(send_data),
		.send_req(send_req),
		.send_ready(send_ready),
		.recv_data(recv_data),
		.recv_valid(recv_valid),
		.sram_addr(sram_addr),
		.sram_data(sram_data),
		.sram_ce_n(sram_ce_n),
		.sram_oe_n(sram_oe_n),
		.sram_we_n(sram_we_n));

endmodule
