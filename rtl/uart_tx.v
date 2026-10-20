`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// uart_tx : 8N1 UART transmitter
//------------------------------------------------------------------------------
module uart_tx #(
    parameter CLK_HZ = 12_000_000,
    parameter BAUD   = 115_200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       start,      // 1-clk pulse: send 'data'
    input  wire [7:0] data,
    output reg        tx,
    output reg        busy,
    output reg        done        // 1-clk pulse at end of stop bit
);
    localparam integer CPB = CLK_HZ / BAUD;      // clocks per bit (104 @ 12 MHz)

    localparam ST_IDLE = 1'b0, ST_SEND = 1'b1;
    reg        st   = ST_IDLE;
    reg [15:0] cnt  = 16'd0;
    reg [3:0]  bit_i = 4'd0;
    reg [9:0]  sh   = 10'h3FF;

    initial begin tx = 1'b1; busy = 1'b0; done = 1'b0; end

    always @(posedge clk) begin
        done <= 1'b0;
        if (rst) begin
            st <= ST_IDLE; tx <= 1'b1; busy <= 1'b0;
        end else begin
            case (st)
                ST_IDLE: begin
                    tx <= 1'b1;
                    if (start) begin
                        sh    <= {1'b1, data, 1'b0};   // stop, data[7:0], start
                        cnt   <= CPB - 1;
                        bit_i <= 4'd0;
                        busy  <= 1'b1;
                        st    <= ST_SEND;
                    end
                end
                ST_SEND: begin
                    tx <= sh[0];
                    if (cnt == 0) begin
                        cnt <= CPB - 1;
                        sh  <= {1'b1, sh[9:1]};
                        if (bit_i == 4'd9) begin
                            st   <= ST_IDLE;
                            busy <= 1'b0;
                            done <= 1'b1;
                        end else
                            bit_i <= bit_i + 4'd1;
                    end else
                        cnt <= cnt - 16'd1;
                end
            endcase
        end
    end
endmodule