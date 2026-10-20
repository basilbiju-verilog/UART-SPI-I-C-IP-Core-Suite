`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// uart_rx : 8N1 UART receiver (mid-bit sampling)
//------------------------------------------------------------------------------
module uart_rx #(
    parameter CLK_HZ = 12_000_000,
    parameter BAUD   = 115_200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid       // 1-clk pulse when a byte is received
);
    localparam integer CPB = CLK_HZ / BAUD;

    localparam [1:0] ST_IDLE = 2'd0, ST_START = 2'd1, ST_DATA = 2'd2, ST_STOP = 2'd3;

    reg [1:0]  rx_s = 2'b11;
    reg [1:0]  st   = ST_IDLE;
    reg [15:0] cnt  = 16'd0;
    reg [2:0]  bit_i = 3'd0;
    reg [7:0]  sh   = 8'd0;

    initial begin data = 8'd0; valid = 1'b0; end

    always @(posedge clk) begin
        rx_s  <= {rx_s[0], rx};
        valid <= 1'b0;
        if (rst) begin
            st <= ST_IDLE;
        end else begin
            case (st)
                ST_IDLE: if (!rx_s[1]) begin
                    cnt <= (CPB / 2) - 1;
                    st  <= ST_START;
                end
                ST_START: begin
                    if (cnt == 0) begin
                        if (!rx_s[1]) begin          // valid start bit
                            cnt   <= CPB - 1;
                            bit_i <= 3'd0;
                            st    <= ST_DATA;
                        end else
                            st <= ST_IDLE;           // glitch
                    end else
                        cnt <= cnt - 16'd1;
                end
                ST_DATA: begin
                    if (cnt == 0) begin
                        sh  <= {rx_s[1], sh[7:1]};   // LSB first
                        cnt <= CPB - 1;
                        if (bit_i == 3'd7) st <= ST_STOP;
                        else bit_i <= bit_i + 3'd1;
                    end else
                        cnt <= cnt - 16'd1;
                end
                ST_STOP: begin
                    if (cnt == 0) begin
                        if (rx_s[1]) begin
                            data  <= sh;
                            valid <= 1'b1;
                        end
                        st <= ST_IDLE;
                    end else
                        cnt <= cnt - 16'd1;
                end
            endcase
        end
    end
endmodule