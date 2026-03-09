// SPDX-FileCopyrightText: © 2023-2026 Uri Shaked <uri@tinytapeout.com>, Hirosh Dabui <hirosh@dabui.de>
// SPDX-License-Identifier: MIT

`default_nettype none
`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// 2-to-4 decoder with active-low enable and active-low outputs
// Similar in behavior to one half of a 74LS139
// -----------------------------------------------------------------------------
module decoder_2to4_n (
    input  wire en_n,
    input  wire a1,
    input  wire a0,
    output wire y0_n,
    output wire y1_n,
    output wire y2_n,
    output wire y3_n
);
  assign y0_n = en_n |  a1 |  a0;
  assign y1_n = en_n |  a1 | ~a0;
  assign y2_n = en_n | ~a1 |  a0;
  assign y3_n = en_n | ~a1 | ~a0;
endmodule

module tb ();

  initial begin
    $dumpfile("tb.fst");
    $dumpvars(0, tb);
    #1;
  end

  reg clk;
  reg rst_n;
  reg ena;
  wire [7:0] uio_in;

  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;

  reg spi_sio1_so_miso0;
  reg uart_rx;
  reg test_sel;

  // uo_out mapping for tt_um_kianv_sv32_soc:
  // [0] = uart_tx, [1] = gpio_out, [2] = spi_cen1
  // [3] = spi_mosi, [4] = spi_cen0, [5] = spi_sclk
  // [6] = spi_cen2 (NOR flash CS), [7] = spi_cen3
  wire uart_tx             = uo_out[0];
  wire gpio_out            = uo_out[1];
  wire spi_cen0            = uo_out[4];
  wire spi_sclk0           = uo_out[5];
  wire spi_sio0_si_mosi0   = uo_out[3];
  wire spi_cen2            = uo_out[6];
  wire uo_out7             = uo_out[7];

  // --- SPI NOR Flash ---
  wire nor_miso;
  pullup(nor_miso);

  spiflash #(
      .FILENAME("firmware/firmware.hex")
  ) spiflash_I (
      .csb(spi_cen2),
      .clk(spi_sclk0),
      .io0(spi_sio0_si_mosi0),
      .io1(nor_miso),
      .io2(),
      .io3()
  );

  wire miso_to_soc = (!spi_cen2) ? nor_miso : spi_sio1_so_miso0;

  // ui_in mapping: [1]=gpio0_in(test_sel), [2]=spi_miso, [7]=uart_rx
  wire [7:0] ui_in = {uart_rx, 4'b0, miso_to_soc, test_sel, 1'b0};

  tt_um_kianv_sv32_soc tt_um_kianv_sv32_soc_I (
      .ui_in  (ui_in),
      .uo_out (uo_out),
      .uio_in (uio_in),
      .uio_out(uio_out),
      .uio_oe (uio_oe),
      .ena    (ena),
      .clk    (clk),
      .rst_n  (rst_n)
  );

  // --- kianv_smem (QSPI) wiring for PSRAM ---
  wire kvsmem_sclk = uio_out[3];
  wire kvsmem_ss_n = uio_out[0];
  wire kvsmem_a0   = uio_out[6];
  wire kvsmem_a1   = uio_out[7];

  wire sio_io0 = uio_oe[1] ? uio_out[1] : 1'bz;
  wire sio_io1 = uio_oe[2] ? uio_out[2] : 1'bz;
  wire sio_io2 = uio_oe[4] ? uio_out[4] : 1'bz;
  wire sio_io3 = uio_oe[5] ? uio_out[5] : 1'bz;

  assign uio_in = {
      kvsmem_a1,
      kvsmem_a0,
      sio_io3,
      sio_io2,
      kvsmem_sclk,
      sio_io1,
      sio_io0,
      kvsmem_ss_n
  };

  wire psram_enable_n = kvsmem_ss_n;

  wire psram0_cs_n;
  wire psram1_cs_n;
  wire psram2_cs_n;
  wire psram3_cs_n;

  decoder_2to4_n psram_cs_decode_I (
      .en_n(psram_enable_n),
      .a1  (kvsmem_a1),
      .a0  (kvsmem_a0),
      .y0_n(psram0_cs_n),
      .y1_n(psram1_cs_n),
      .y2_n(psram2_cs_n),
      .y3_n(psram3_cs_n)
  );

  psram psram0_I (
      .ce_n(psram0_cs_n),
      .sck (kvsmem_sclk),
      .dio ({sio_io3, sio_io2, sio_io1, sio_io0})
  );

  psram psram1_I (
      .ce_n(psram1_cs_n),
      .sck (kvsmem_sclk),
      .dio ({sio_io3, sio_io2, sio_io1, sio_io0})
  );

  psram psram2_I (
      .ce_n(psram2_cs_n),
      .sck (kvsmem_sclk),
      .dio ({sio_io3, sio_io2, sio_io1, sio_io0})
  );

  psram psram3_I (
      .ce_n(psram3_cs_n),
      .sck (kvsmem_sclk),
      .dio ({sio_io3, sio_io2, sio_io1, sio_io0})
  );

endmodule
