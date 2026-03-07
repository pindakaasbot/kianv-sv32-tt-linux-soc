// SPDX-License-Identifier: Apache-2.0
/*
 * KianV RISC-V Linux/XV6 SoC — Register File
 * Uses rf_top (SRAM-backed on ASIC, FF-based in sim)
 */

`default_nettype none

module register_file (
    input  wire        clk,
    input  wire        we,
    input  wire [ 4:0] A1,
    input  wire [ 4:0] A2,
    input  wire [ 4:0] A3,
    input  wire [31:0] wd,
    output wire [31:0] rd1,
    output wire [31:0] rd2
);

  wire [31:0] ra_data;
  wire [31:0] rb_data;

  rf_top tnt_regfile (
      .w_data (wd),
      .w_addr (A3),
      .w_ena  (we),
      .ra_addr(A1),
      .rb_addr(A2),
      .ra_data(ra_data),
      .rb_data(rb_data),
      .clk    (clk)
  );

  assign rd1 = A1 != 0 ? ra_data : 32'b0;
  assign rd2 = A2 != 0 ? rb_data : 32'b0;

endmodule
