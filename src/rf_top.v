// Register file storage using 1x RM_IHPSG13_2P_64x32_c2 SRAM macro
// Multi-cycle CPU: reads and writes happen in different FSM states,
// so Port A handles rd1 reads + writes (time-multiplexed),
// Port B handles rd2 reads only.
// Write forwarding: if reading address being written, bypass with write data.

`default_nettype none

module rf_top (
    input  wire [31:0] w_data,
    input  wire [ 4:0] w_addr,
    input  wire        w_ena,
    input  wire [ 4:0] ra_addr,
    input  wire [ 4:0] rb_addr,
    output reg  [31:0] ra_data,
    output reg  [31:0] rb_data,
    input  wire        clk
);

`ifdef SYNTHESIS
  // SRAM macro instance for ASIC synthesis
  wire [31:0] sram_a_dout;
  wire [31:0] sram_b_dout;

  // Port A: reads ra_addr when idle, writes w_addr during writeback
  // Port B: always reads rb_addr (never writes)
  RM_IHPSG13_2P_64x32_c2 u_sram_rd1 (
      .A_CLK (clk),
      .A_MEN (1'b1),
      .A_WEN (w_ena),
      .A_REN (~w_ena),
      .A_ADDR({1'b0, w_ena ? w_addr : ra_addr}),
      .A_DIN (w_data),
      .A_DLY (1'b0),
      .A_DOUT(sram_a_dout),
      .B_CLK (clk),
      .B_MEN (1'b1),
      .B_WEN (1'b0),
      .B_REN (1'b1),
      .B_ADDR({1'b0, rb_addr}),
      .B_DIN (32'b0),
      .B_DLY (1'b0),
      .B_DOUT(sram_b_dout)
  );

  // Write forwarding: if reading address just written, bypass
  reg        fwd_a, fwd_b;
  reg [31:0] fwd_data;

  always @(posedge clk) begin
    fwd_a    <= w_ena && (ra_addr == w_addr);
    fwd_b    <= w_ena && (rb_addr == w_addr);
    fwd_data <= w_data;
  end

  always @(*) begin
    ra_data = fwd_a ? fwd_data : sram_a_dout;
    rb_data = fwd_b ? fwd_data : sram_b_dout;
  end

`else
  // Behavioral model for simulation
  reg [31:0] storage[0:31];

  always @(posedge clk) begin
    if (w_ena) storage[w_addr] <= w_data;

    if (w_ena && (ra_addr == w_addr)) ra_data <= w_data;
    else ra_data <= storage[ra_addr];

    if (w_ena && (rb_addr == w_addr)) rb_data <= w_data;
    else rb_data <= storage[rb_addr];
  end
`endif

endmodule

`default_nettype wire
