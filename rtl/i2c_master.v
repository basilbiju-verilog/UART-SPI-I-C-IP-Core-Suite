`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// i2c_master : byte-level I2C master (open-drain style outputs)
//   cmd 0 = START (also used as repeated START)
//   cmd 1 = STOP
//   cmd 2 = WRITE one byte  -> ack_out = 0 means slave ACKed
//   cmd 3 = READ  one byte  -> ack_in  = 0 send ACK, 1 send NACK (last byte)
// scl_oe / sda_oe = 1 means "pull the line LOW"; 0 means "release" (pull-up).
// No clock stretching support (slave model never stretches).
//------------------------------------------------------------------------------
module i2c_master #(
    parameter CLK_HZ = 12_000_000,
    parameter I2C_HZ = 100_000
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       cmd_valid,    // 1-clk pulse (ignored while busy)
    input  wire [1:0] cmd,
    input  wire [7:0] wdata,
    input  wire       ack_in,
    output reg        busy,
    output reg        done,         // 1-clk pulse
    output reg  [7:0] rdata,
    output reg        ack_out,
    output reg        scl_oe,
    output reg        sda_oe,
    input  wire       scl_i,
    input  wire       sda_i
);
    localparam [1:0] CMD_START = 2'd0, CMD_STOP = 2'd1, CMD_WRITE = 2'd2, CMD_READ = 2'd3;
    localparam integer QDIV = CLK_HZ / (I2C_HZ * 4);     // quarter-bit ticks

    localparam ST_IDLE = 1'b0, ST_RUN = 1'b1;
    reg        st     = ST_IDLE;
    reg [1:0]  cmd_r  = 2'd0;
    reg [1:0]  phase  = 2'd0;
    reg [3:0]  bitn   = 4'd0;
    reg [15:0] qcnt   = 16'd0;
    reg [7:0]  shreg  = 8'd0;
    reg        ack_r  = 1'b0;
    reg [1:0]  sda_s  = 2'b11;

    initial begin
        busy = 1'b0; done = 1'b0; rdata = 8'd0; ack_out = 1'b1;
        scl_oe = 1'b0; sda_oe = 1'b0;
    end

    always @(posedge clk) begin
        sda_s <= {sda_s[0], sda_i};
        done  <= 1'b0;
        if (rst) begin
            st <= ST_IDLE; busy <= 1'b0; scl_oe <= 1'b0; sda_oe <= 1'b0;
        end else if (st == ST_IDLE) begin
            if (cmd_valid) begin
                cmd_r <= cmd;
                shreg <= wdata;
                ack_r <= ack_in;
                phase <= 2'd0;
                bitn  <= 4'd0;
                qcnt  <= 16'd0;
                busy  <= 1'b1;
                st    <= ST_RUN;
            end
        end else begin
            if (qcnt == QDIV - 1) begin
                qcnt <= 16'd0;
                case (cmd_r)
                    CMD_START: case (phase)
                        2'd0: sda_oe <= 1'b0;          // SDA high
                        2'd1: scl_oe <= 1'b0;          // SCL high
                        2'd2: sda_oe <= 1'b1;          // SDA falls -> START
                        2'd3: scl_oe <= 1'b1;          // SCL low
                    endcase
                    CMD_STOP: case (phase)
                        2'd0: sda_oe <= 1'b1;          // SDA low (SCL low)
                        2'd1: scl_oe <= 1'b0;          // SCL high
                        2'd2: sda_oe <= 1'b0;          // SDA rises -> STOP
                        default: ;
                    endcase
                    CMD_WRITE: case (phase)
                        2'd0: sda_oe <= (bitn < 4'd8) ? ~shreg[7] : 1'b0;  // bit 8 = ACK slot
                        2'd1: scl_oe <= 1'b0;
                        2'd2: if (bitn == 4'd8) ack_out <= sda_s[1];
                        2'd3: begin
                            scl_oe <= 1'b1;
                            if (bitn < 4'd8) shreg <= {shreg[6:0], 1'b0};
                        end
                    endcase
                    CMD_READ: case (phase)
                        2'd0: sda_oe <= (bitn < 4'd8) ? 1'b0 : ~ack_r;     // bit 8 = our ACK/NACK
                        2'd1: scl_oe <= 1'b0;
                        2'd2: if (bitn < 4'd8) shreg <= {shreg[6:0], sda_s[1]};
                        2'd3: scl_oe <= 1'b1;
                    endcase
                endcase

                if (phase == 2'd3) begin
                    phase <= 2'd0;
                    if ((cmd_r == CMD_WRITE || cmd_r == CMD_READ) && bitn != 4'd8)
                        bitn <= bitn + 4'd1;
                    else begin
                        st    <= ST_IDLE;
                        busy  <= 1'b0;
                        done  <= 1'b1;
                        rdata <= shreg;
                    end
                end else
                    phase <= phase + 2'd1;
            end else
                qcnt <= qcnt + 16'd1;
        end
    end
endmodule