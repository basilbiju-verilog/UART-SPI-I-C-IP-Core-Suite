`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// spi_master : SPI mode 0 (CPOL=0, CPHA=0), 8-bit, MSB first, CS handled here
// SCLK frequency = CLK_HZ / (2*CLK_DIV)   (12 MHz / 24 = 500 kHz by default)
//------------------------------------------------------------------------------
module spi_master #(
    parameter CLK_DIV = 12
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       start,        // 1-clk pulse (ignored while busy)
    input  wire [7:0] tx_data,
    output reg  [7:0] rx_data,
    output reg        busy,
    output reg        done,         // 1-clk pulse, rx_data valid
    output reg        sclk,
    output reg        mosi,
    output reg        cs_n,
    input  wire       miso
);
    localparam [1:0] ST_IDLE = 2'd0, ST_LEAD = 2'd1, ST_RUN = 2'd2, ST_TRAIL = 2'd3;

    reg [1:0]  st    = ST_IDLE;
    reg [15:0] cnt   = 16'd0;
    reg [3:0]  bitc  = 4'd0;
    reg [7:0]  sh_tx = 8'd0;
    reg [7:0]  sh_rx = 8'd0;
    reg [1:0]  miso_s = 2'b00;

    initial begin
        rx_data = 8'd0; busy = 1'b0; done = 1'b0;
        sclk = 1'b0; mosi = 1'b0; cs_n = 1'b1;
    end

    always @(posedge clk) begin
        miso_s <= {miso_s[0], miso};
        done   <= 1'b0;
        if (rst) begin
            st <= ST_IDLE; sclk <= 1'b0; mosi <= 1'b0; cs_n <= 1'b1; busy <= 1'b0;
        end else begin
            case (st)
                ST_IDLE: begin
                    sclk <= 1'b0;
                    cs_n <= 1'b1;
                    if (start) begin
                        sh_tx <= tx_data;
                        mosi  <= tx_data[7];
                        cs_n  <= 1'b0;
                        busy  <= 1'b1;
                        cnt   <= 16'd0;
                        bitc  <= 4'd0;
                        st    <= ST_LEAD;
                    end
                end
                ST_LEAD: begin                         // CS setup time
                    if (cnt == CLK_DIV - 1) begin cnt <= 16'd0; st <= ST_RUN; end
                    else cnt <= cnt + 16'd1;
                end
                ST_RUN: begin
                    if (cnt == CLK_DIV - 1) begin
                        cnt  <= 16'd0;
                        sclk <= ~sclk;
                        if (!sclk) begin               // rising edge: sample MISO
                            sh_rx <= {sh_rx[6:0], miso_s[1]};
                        end else begin                 // falling edge: next MOSI bit
                            bitc <= bitc + 4'd1;
                            if (bitc == 4'd7) st <= ST_TRAIL;
                            else begin
                                sh_tx <= {sh_tx[6:0], 1'b0};
                                mosi  <= sh_tx[6];
                            end
                        end
                    end else
                        cnt <= cnt + 16'd1;
                end
                ST_TRAIL: begin                        // CS hold time
                    if (cnt == CLK_DIV - 1) begin
                        cnt     <= 16'd0;
                        cs_n    <= 1'b1;
                        rx_data <= sh_rx;
                        done    <= 1'b1;
                        busy    <= 1'b0;
                        st      <= ST_IDLE;
                    end else
                        cnt <= cnt + 16'd1;
                end
            endcase
        end
    end
endmodule