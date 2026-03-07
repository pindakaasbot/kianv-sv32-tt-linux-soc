// SPDX-FileCopyrightText: © 2023-2026 Uri Shaked <uri@tinytapeout.com>, Hirosh Dabui <hirosh@dabui.de>
// SPDX-License-Identifier: MIT

`default_nettype none
`timescale 1ns / 1ps

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

`ifdef GL_TEST
  wire VPWR = 1'b1;
  wire VGND = 1'b0;
`endif

  // SPI slave MISO (driven by cocotb SPI slave coroutine)
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
  wire spi_cen2            = uo_out[6];  // NOR flash chip select
  wire uo_out7             = uo_out[7];

  // --- SPI NOR Flash (boots CPU from 0x20000000) ---
  // Connected to the shared SPI bus (uo_out pins), NOR_CS_IDX=2 → uo_out[6]
  wire nor_miso;
  pullup(nor_miso);  // default high when flash not driving

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

  // MISO mux: NOR flash active → flash MISO, else → SPI slave MISO
  wire miso_to_soc = (!spi_cen2) ? nor_miso : spi_sio1_so_miso0;

  // ui_in mapping: [1]=gpio0_in(test_sel), [2]=spi_miso, [7]=uart_rx
  wire [7:0] ui_in = {uart_rx, 4'b0, miso_to_soc, test_sel, 1'b0};

  tt_um_kianv_sv32_soc tt_um_kianv_sv32_soc_I (
`ifdef GL_TEST
      .VPWR(VPWR),
      .VGND(VGND),
`endif
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
  wire kvsmem_csn0 = uio_out[6];
  wire kvsmem_csn1 = uio_out[7];

  // Bidirectional SIO lines
  wire sio_io0 = uio_oe[1] ? uio_out[1] : 1'bz;
  wire sio_io1 = uio_oe[2] ? uio_out[2] : 1'bz;
  wire sio_io2 = uio_oe[4] ? uio_out[4] : 1'bz;
  wire sio_io3 = uio_oe[5] ? uio_out[5] : 1'bz;

  assign uio_in = {kvsmem_csn1, kvsmem_csn0, sio_io3, sio_io2, kvsmem_sclk, sio_io1, sio_io0, kvsmem_ss_n};

  // PSRAM chip 0 — CSN[0] region (0x80000000-0x807FFFFF)
  wire psram0_cs = kvsmem_ss_n | kvsmem_csn0;

  psram psram0_I (
      .ce_n(psram0_cs),
      .sck (kvsmem_sclk),
      .dio ({sio_io3, sio_io2, sio_io1, sio_io0})
  );

  // PSRAM chip 1 — CSN[1] region (0x80800000-0x80FFFFFF)
  wire psram1_cs = kvsmem_ss_n | kvsmem_csn1;

  psram psram1_I (
      .ce_n(psram1_cs),
      .sck (kvsmem_sclk),
      .dio ({sio_io3, sio_io2, sio_io1, sio_io0})
  );

endmodule