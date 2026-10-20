`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// spi_slave_model : synthesizable SPI mode-0 slave (runs on the system clock)
//
// Behaviour (used by the self-test):
//   * First transfer returns INIT_RESP (0x3C)
//   * Every later transfer returns the bitwise INVERSE of the byte received
//     in the previous transfer.
//   -> the master checks both its MOSI path (via the next reply) and MISO path.
//------------------------------------------------------------------------------
module spi_slave_model #(
    parameter [7:0] INIT_RESP = 8'h3C
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       sclk,
    input  wire       mosi,
    input  wire       cs_n,
    output wire       miso,
    output reg  [7:0] rx_byte,
    output reg        rx_valid
);
    reg [2:0] sclk_s = 3'b000;
    reg [1:0] mosi_s = 2'b00;
    reg [1:0] cs_s   = 2'b11;

    always @(posedge clk) begin
        sclk_s <= {sclk_s[1:0], sclk};
        mosi_s <= {mosi_s[0],  mosi};
        cs_s   <= {cs_s[0],    cs_n};
    end

    wire rise  =  sclk_s[1] & ~sclk_s[2];
    wire fall  = ~sclk_s[1] &  sclk_s[2];
    wire cs_hi =  cs_s[1];

    reg [7:0] sh_in   = 8'd0;
    reg [7:0] sh_out  = INIT_RESP;
    reg [7:0] preload = INIT_RESP;
    reg [2:0] bitc    = 3'd0;

    assign miso = sh_out[7];

    initial begin rx_byte = 8'd0; rx_valid = 1'b0; end

    always @(posedge clk) begin
        rx_valid <= 1'b0;
        if (rst) begin
            sh_out  <= INIT_RESP;
            preload <= INIT_RESP;
            bitc    <= 3'd0;
        end else if (cs_hi) begin
            sh_out <= preload;
            bitc   <= 3'd0;
        end else begin
            if (rise) begin
                sh_in <= {sh_in[6:0], mosi_s[1]};
                bitc  <= bitc + 3'd1;
                if (bitc == 3'd7) begin
                    rx_byte  <= {sh_in[6:0], mosi_s[1]};
                    rx_valid <= 1'b1;
                    preload  <= ~{sh_in[6:0], mosi_s[1]};
                end
            end
            if (fall)
                sh_out <= {sh_out[6:0], 1'b0};
        end
    end
endmodule