`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// i2c_slave_model : synthesizable I2C slave with a 16-byte register file
//   * 7-bit address ADDR (default 0x42)
//   * Write: [addr+W][reg ptr][data0][data1]...   (pointer auto-increments)
//   * Read : [addr+W][reg ptr] RESTART [addr+R][data0][data1]...
//------------------------------------------------------------------------------
module i2c_slave_model #(
    parameter [6:0] ADDR = 7'h42
)(
    input  wire clk,
    input  wire rst,
    input  wire scl_i,
    input  wire sda_i,
    output wire sda_oe          // 1 = pull SDA low
);
    reg [2:0] scl_s = 3'b111;
    reg [2:0] sda_s = 3'b111;
    always @(posedge clk) begin
        scl_s <= {scl_s[1:0], scl_i};
        sda_s <= {sda_s[1:0], sda_i};
    end

    wire sda       = sda_s[1];
    wire scl_rise  =  scl_s[1] & ~scl_s[2];
    wire scl_fall  = ~scl_s[1] &  scl_s[2];
    wire sda_rise  =  sda_s[1] & ~sda_s[2];
    wire sda_fall  = ~sda_s[1] &  sda_s[2];
    wire start_c   = sda_fall & scl_s[1];     // SDA falls while SCL high
    wire stop_c    = sda_rise & scl_s[1];     // SDA rises while SCL high

    localparam [2:0] S_IDLE = 3'd0, S_ADDR = 3'd1, S_ACK1 = 3'd2, S_ACK2 = 3'd3,
                     S_RX   = 3'd4, S_TX   = 3'd5, S_TXACK = 3'd6;

    reg [2:0] st      = S_IDLE;
    reg [3:0] bitc    = 4'd0;
    reg [7:0] sh      = 8'd0;
    reg       rw      = 1'b0;
    reg       got_ptr = 1'b0;
    reg [3:0] ptr     = 4'd0;
    reg       drive   = 1'b0;
    reg       mnack   = 1'b1;
    reg [7:0] mem [0:15];
    integer   k;
    initial for (k = 0; k < 16; k = k + 1) mem[k] = 8'h00;

    wire [7:0] rx_byte = {sh[6:0], sda};
    wire [3:0] ptr_n   = ptr + 4'd1;

    assign sda_oe = drive;

    always @(posedge clk) begin
        if (rst) begin
            st <= S_IDLE; drive <= 1'b0; got_ptr <= 1'b0;
        end else if (start_c) begin
            st <= S_ADDR; bitc <= 4'd0; sh <= 8'd0; got_ptr <= 1'b0; drive <= 1'b0;
        end else if (stop_c) begin
            st <= S_IDLE; drive <= 1'b0;
        end else begin
            case (st)
                S_IDLE: ;

                S_ADDR: if (scl_rise) begin
                    sh <= rx_byte;
                    if (bitc == 4'd7) begin
                        rw <= rx_byte[0];
                        if (rx_byte[7:1] == ADDR) st <= S_ACK1;
                        else                      st <= S_IDLE;     // not for us
                    end else
                        bitc <= bitc + 4'd1;
                end

                S_ACK1: if (scl_fall) begin          // after 8th clock: drive ACK
                    drive <= 1'b1;
                    st    <= S_ACK2;
                end

                S_ACK2: if (scl_fall) begin          // after 9th clock: release / start TX
                    bitc <= 4'd0;
                    if (rw) begin
                        sh    <= mem[ptr];
                        drive <= ~mem[ptr][7];
                        st    <= S_TX;
                    end else begin
                        drive <= 1'b0;
                        st    <= S_RX;
                    end
                end

                S_RX: if (scl_rise) begin
                    sh <= rx_byte;
                    if (bitc == 4'd7) begin
                        if (!got_ptr) begin
                            ptr     <= rx_byte[3:0];
                            got_ptr <= 1'b1;
                        end else begin
                            mem[ptr] <= rx_byte;
                            ptr      <= ptr_n;
                        end
                        st <= S_ACK1;
                    end else
                        bitc <= bitc + 4'd1;
                end

                S_TX: if (scl_fall) begin
                    if (bitc == 4'd7) begin
                        drive <= 1'b0;               // release for master ACK/NACK
                        st    <= S_TXACK;
                    end else begin
                        bitc  <= bitc + 4'd1;
                        sh    <= {sh[6:0], 1'b0};
                        drive <= ~sh[6];
                    end
                end

                S_TXACK: begin
                    if (scl_rise) mnack <= sda;
                    if (scl_fall) begin
                        if (!mnack) begin            // master ACKed -> next byte
                            ptr   <= ptr_n;
                            sh    <= mem[ptr_n];
                            drive <= ~mem[ptr_n][7];
                            bitc  <= 4'd0;
                            st    <= S_TX;
                        end else begin
                            drive <= 1'b0;
                            st    <= S_IDLE;
                        end
                    end
                end

                default: st <= S_IDLE;
            endcase
        end
    end
endmodule