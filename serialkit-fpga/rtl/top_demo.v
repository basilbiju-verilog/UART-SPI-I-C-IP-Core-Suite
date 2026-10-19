`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// top_demo : Cmod A7-35T  UART + SPI + I2C loopback self-test
//
//  PC <--UART--> top_demo FSM --> SPI master --jumpers--> SPI slave model
//                             --> I2C master --jumpers--> I2C slave model
//                             --> LEDs (PASS / FAIL) + UART report
//
//  Start a test run by: BTN0, or sending ANY byte over the UART, (or at power-up
//  when AUTO_RUN = 1).  BTN1 = reset.
//  RGB LED : blue = running, green = all PASS, red = any FAIL
//  LD1 = SPI pass, LD2 = I2C pass
//  UART report: "SPI:PASS I2C:PASS\r\n"  (115200 8N1)
//
//  EXT_LOOPBACK = 1 : signals really leave the FPGA and come back through jumper wires
//  EXT_LOOPBACK = 0 : loopback done inside the FPGA (no wires needed, for bring-up)
//------------------------------------------------------------------------------
module top_demo #(
    parameter CLK_HZ          = 12_000_000,
    parameter BAUD            = 115_200,
    parameter SPI_CLK_DIV     = 12,           // SCLK = 12 MHz / 24 = 500 kHz
    parameter I2C_HZ          = 100_000,
    parameter EXT_LOOPBACK    = 0,
    parameter AUTO_RUN        = 1,
    parameter DEBOUNCE_CYCLES = 120_000       // 10 ms @ 12 MHz
)(
    input  wire       clk,
    input  wire [1:0] btn,
    output wire [1:0] led,
    output wire       led0_r,
    output wire       led0_g,
    output wire       led0_b,

    // UART to PC (through the on-board FTDI)
    input  wire       uart_txd_in,    // PC -> FPGA
    output wire       uart_rxd_out,   // FPGA -> PC

    // SPI master side
    output wire       spi_sclk_o,
    output wire       spi_mosi_o,
    output wire       spi_cs_o,
    input  wire       spi_miso_i,
    // SPI slave side
    input  wire       spi_sclk_i,
    input  wire       spi_mosi_i,
    input  wire       spi_cs_i,
    output wire       spi_miso_o,

    // I2C master side
    inout  wire       i2c_scl_m,
    inout  wire       i2c_sda_m,
    // I2C slave side
    input  wire       i2c_scl_s,
    inout  wire       i2c_sda_s
);
    localparam [6:0] I2C_ADDR = 7'h42;

    //--------------------------------------------------------------------------
    // Reset: power-on counter + BTN1
    //--------------------------------------------------------------------------
    reg [7:0] por_cnt = 8'd0;
    reg [1:0] rst_s   = 2'b00;
    always @(posedge clk) begin
        if (!por_cnt[7]) por_cnt <= por_cnt + 8'd1;
        rst_s <= {rst_s[0], btn[1]};
    end
    wire rst = ~por_cnt[7] | rst_s[1];

    //--------------------------------------------------------------------------
    // BTN0 debounce + rising-edge detect
    //--------------------------------------------------------------------------
    reg [1:0]  b0_sync   = 2'b00;
    reg        b0_stable = 1'b0;
    reg        b0_prev   = 1'b0;
    reg [19:0] db_cnt    = 20'd0;
    always @(posedge clk) begin
        b0_sync <= {b0_sync[0], btn[0]};
        b0_prev <= b0_stable;
        if (b0_sync[1] == b0_stable)
            db_cnt <= 20'd0;
        else begin
            db_cnt <= db_cnt + 20'd1;
            if (db_cnt >= DEBOUNCE_CYCLES) begin
                b0_stable <= b0_sync[1];
                db_cnt    <= 20'd0;
            end
        end
    end
    wire btn_start = b0_stable & ~b0_prev;

    //--------------------------------------------------------------------------
    // UART
    //--------------------------------------------------------------------------
    reg        tx_start = 1'b0;
    reg  [7:0] tx_data  = 8'd0;
    wire       tx_busy, tx_done;
    wire [7:0] rx_data;
    wire       rx_valid;

    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_tx (
        .clk(clk), .rst(rst), .start(tx_start), .data(tx_data),
        .tx(uart_rxd_out), .busy(tx_busy), .done(tx_done));

    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_rx (
        .clk(clk), .rst(rst), .rx(uart_txd_in), .data(rx_data), .valid(rx_valid));

    //--------------------------------------------------------------------------
    // SPI master + slave model
    //--------------------------------------------------------------------------
    reg        spi_start = 1'b0;
    reg  [7:0] spi_tx    = 8'd0;
    wire [7:0] spi_rx;
    wire       spi_busy, spi_done;
    wire       m_sclk, m_mosi, m_cs_n, s_miso;

    wire sl_sclk = (EXT_LOOPBACK != 0) ? spi_sclk_i : m_sclk;
    wire sl_mosi = (EXT_LOOPBACK != 0) ? spi_mosi_i : m_mosi;
    wire sl_cs_n = (EXT_LOOPBACK != 0) ? spi_cs_i   : m_cs_n;
    wire m_miso  = (EXT_LOOPBACK != 0) ? spi_miso_i : s_miso;

    assign spi_sclk_o = m_sclk;
    assign spi_mosi_o = m_mosi;
    assign spi_cs_o   = m_cs_n;
    assign spi_miso_o = s_miso;

    spi_master #(.CLK_DIV(SPI_CLK_DIV)) u_spi_m (
        .clk(clk), .rst(rst), .start(spi_start), .tx_data(spi_tx),
        .rx_data(spi_rx), .busy(spi_busy), .done(spi_done),
        .sclk(m_sclk), .mosi(m_mosi), .cs_n(m_cs_n), .miso(m_miso));

    spi_slave_model #(.INIT_RESP(8'h3C)) u_spi_s (
        .clk(clk), .rst(rst), .sclk(sl_sclk), .mosi(sl_mosi), .cs_n(sl_cs_n),
        .miso(s_miso), .rx_byte(), .rx_valid());

    //--------------------------------------------------------------------------
    // I2C master + slave model (open-drain bus)
    //--------------------------------------------------------------------------
    reg        i2c_valid  = 1'b0;
    reg  [1:0] i2c_cmd    = 2'd0;
    reg  [7:0] i2c_wdata  = 8'd0;
    reg        i2c_ack_in = 1'b0;
    wire [7:0] i2c_rdata;
    wire       i2c_ack_out, i2c_busy, i2c_done;
    wire       m_scl_oe, m_sda_oe, s_sda_oe;

    assign i2c_scl_m = m_scl_oe ? 1'b0 : 1'bz;
    assign i2c_sda_m = m_sda_oe ? 1'b0 : 1'bz;
    assign i2c_sda_s = s_sda_oe ? 1'b0 : 1'bz;

    wire scl_int = ~m_scl_oe;                    // internal wired-AND bus
    wire sda_int = ~(m_sda_oe | s_sda_oe);

    wire m_scl_in = (EXT_LOOPBACK != 0) ? i2c_scl_m : scl_int;
    wire m_sda_in = (EXT_LOOPBACK != 0) ? i2c_sda_m : sda_int;
    wire s_scl_in = (EXT_LOOPBACK != 0) ? i2c_scl_s : scl_int;
    wire s_sda_in = (EXT_LOOPBACK != 0) ? i2c_sda_s : sda_int;

    i2c_master #(.CLK_HZ(CLK_HZ), .I2C_HZ(I2C_HZ)) u_i2c_m (
        .clk(clk), .rst(rst), .cmd_valid(i2c_valid), .cmd(i2c_cmd),
        .wdata(i2c_wdata), .ack_in(i2c_ack_in), .busy(i2c_busy), .done(i2c_done),
        .rdata(i2c_rdata), .ack_out(i2c_ack_out),
        .scl_oe(m_scl_oe), .sda_oe(m_sda_oe), .scl_i(m_scl_in), .sda_i(m_sda_in));

    i2c_slave_model #(.ADDR(I2C_ADDR)) u_i2c_s (
        .clk(clk), .rst(rst), .scl_i(s_scl_in), .sda_i(s_sda_in), .sda_oe(s_sda_oe));

    //--------------------------------------------------------------------------
    // Test vectors
    //--------------------------------------------------------------------------
    // SPI: slave replies INIT(0x3C) first, then ~(previous byte we sent).
    // The last byte we send is 0xC3, so the slave's next reply is ~0xC3 = 0x3C
    // again -> the test is repeatable run after run without resetting the slave.
    function [7:0] spi_tx_vec;
        input [1:0] i;
        begin
            case (i)
                2'd0:    spi_tx_vec = 8'hA5;
                2'd1:    spi_tx_vec = 8'h0F;
                default: spi_tx_vec = 8'hC3;
            endcase
        end
    endfunction

    function [7:0] spi_exp_vec;
        input [1:0] i;
        begin
            case (i)
                2'd0:    spi_exp_vec = 8'h3C;     // power-up response
                2'd1:    spi_exp_vec = 8'h5A;     // ~0xA5
                default: spi_exp_vec = 8'hF0;     // ~0x0F
            endcase
        end
    endfunction

    // Report text:  "SPI:PASS I2C:PASS\r\n"   (19 chars)
    function [7:0] msg_char;
        input [4:0] i;
        input       spi_ok;
        input       i2c_ok;
        begin
            case (i)
                5'd0:  msg_char = "S";
                5'd1:  msg_char = "P";
                5'd2:  msg_char = "I";
                5'd3:  msg_char = ":";
                5'd4:  msg_char = spi_ok ? "P" : "F";
                5'd5:  msg_char = "A";
                5'd6:  msg_char = spi_ok ? "S" : "I";
                5'd7:  msg_char = spi_ok ? "S" : "L";
                5'd8:  msg_char = " ";
                5'd9:  msg_char = "I";
                5'd10: msg_char = "2";
                5'd11: msg_char = "C";
                5'd12: msg_char = ":";
                5'd13: msg_char = i2c_ok ? "P" : "F";
                5'd14: msg_char = "A";
                5'd15: msg_char = i2c_ok ? "S" : "I";
                5'd16: msg_char = i2c_ok ? "S" : "L";
                5'd17: msg_char = 8'h0D;
                5'd18: msg_char = 8'h0A;
                default: msg_char = 8'h20;
            endcase
        end
    endfunction

    // I2C step table (combinational on i2c_idx)
    localparam [1:0] CMD_START = 2'd0, CMD_STOP = 2'd1, CMD_WRITE = 2'd2, CMD_READ = 2'd3;
    localparam [3:0] I2C_LAST  = 4'd13;

    reg [3:0] i2c_idx = 4'd0;
    reg [1:0] t_cmd;
    reg [7:0] t_wdata;
    reg       t_ack_in, t_chk_ack, t_chk_data;
    reg [7:0] t_exp;

    always @* begin
        t_cmd = CMD_START; t_wdata = 8'h00; t_ack_in = 1'b0;
        t_chk_ack = 1'b0;  t_chk_data = 1'b0; t_exp = 8'h00;
        case (i2c_idx)
            // --- write 0xC3, 0x3C to registers 5 and 6
            4'd0:  t_cmd = CMD_START;
            4'd1:  begin t_cmd = CMD_WRITE; t_wdata = {I2C_ADDR, 1'b0}; t_chk_ack = 1'b1; end
            4'd2:  begin t_cmd = CMD_WRITE; t_wdata = 8'h05;            t_chk_ack = 1'b1; end
            4'd3:  begin t_cmd = CMD_WRITE; t_wdata = 8'hC3;            t_chk_ack = 1'b1; end
            4'd4:  begin t_cmd = CMD_WRITE; t_wdata = 8'h3C;            t_chk_ack = 1'b1; end
            4'd5:  t_cmd = CMD_STOP;
            // --- read them back (repeated start)
            4'd6:  t_cmd = CMD_START;
            4'd7:  begin t_cmd = CMD_WRITE; t_wdata = {I2C_ADDR, 1'b0}; t_chk_ack = 1'b1; end
            4'd8:  begin t_cmd = CMD_WRITE; t_wdata = 8'h05;            t_chk_ack = 1'b1; end
            4'd9:  t_cmd = CMD_START;
            4'd10: begin t_cmd = CMD_WRITE; t_wdata = {I2C_ADDR, 1'b1}; t_chk_ack = 1'b1; end
            4'd11: begin t_cmd = CMD_READ;  t_ack_in = 1'b0; t_chk_data = 1'b1; t_exp = 8'hC3; end
            4'd12: begin t_cmd = CMD_READ;  t_ack_in = 1'b1; t_chk_data = 1'b1; t_exp = 8'h3C; end
            default: t_cmd = CMD_STOP;                                     // step 13
        endcase
    end

    //--------------------------------------------------------------------------
    // Self-test FSM
    //--------------------------------------------------------------------------
    localparam [3:0] S_IDLE     = 4'd0,
                     S_SPI_GO   = 4'd1,
                     S_SPI_WAIT = 4'd2,
                     S_SPI_GAP  = 4'd3,
                     S_I2C_GO   = 4'd4,
                     S_I2C_WAIT = 4'd5,
                     S_RPT_SEND = 4'd6,
                     S_RPT_WAIT = 4'd7;

    reg [3:0] st        = S_IDLE;
    reg [1:0] spi_idx   = 2'd0;
    reg [7:0] gap       = 8'd0;
    reg [4:0] rpt_idx   = 5'd0;
    reg       spi_fail  = 1'b0;
    reg       i2c_fail  = 1'b0;
    reg       has_run   = 1'b0;
    reg       auto_done = 1'b0;

    wire start_req = rx_valid | btn_start;

    always @(posedge clk) begin
        spi_start <= 1'b0;
        i2c_valid <= 1'b0;
        tx_start  <= 1'b0;

        if (rst) begin
            st <= S_IDLE; spi_fail <= 1'b0; i2c_fail <= 1'b0;
            has_run <= 1'b0; auto_done <= 1'b0;
        end else begin
            case (st)
                S_IDLE: begin
                    if (start_req || (AUTO_RUN != 0 && !auto_done)) begin
                        auto_done <= 1'b1;
                        spi_fail  <= 1'b0;
                        i2c_fail  <= 1'b0;
                        spi_idx   <= 2'd0;
                        i2c_idx   <= 4'd0;
                        rpt_idx   <= 5'd0;
                        st        <= S_SPI_GO;
                    end
                end

                // ---------------- SPI test (3 transfers) ----------------
                S_SPI_GO: begin
                    spi_tx    <= spi_tx_vec(spi_idx);
                    spi_start <= 1'b1;
                    st        <= S_SPI_WAIT;
                end
                S_SPI_WAIT: if (spi_done) begin
                    if (spi_rx != spi_exp_vec(spi_idx)) spi_fail <= 1'b1;
                    gap <= 8'd0;
                    st  <= S_SPI_GAP;
                end
                S_SPI_GAP: begin                       // CS-high gap between transfers
                    gap <= gap + 8'd1;
                    if (gap == 8'hFF) begin
                        if (spi_idx == 2'd2) begin
                            i2c_idx <= 4'd0;
                            st      <= S_I2C_GO;
                        end else begin
                            spi_idx <= spi_idx + 2'd1;
                            st      <= S_SPI_GO;
                        end
                    end
                end

                // ---------------- I2C test (14 steps) -------------------
                S_I2C_GO: begin
                    i2c_cmd    <= t_cmd;
                    i2c_wdata  <= t_wdata;
                    i2c_ack_in <= t_ack_in;
                    i2c_valid  <= 1'b1;
                    st         <= S_I2C_WAIT;
                end
                S_I2C_WAIT: if (i2c_done) begin
                    if (t_chk_ack  && i2c_ack_out)           i2c_fail <= 1'b1;
                    if (t_chk_data && (i2c_rdata != t_exp))  i2c_fail <= 1'b1;
                    if (i2c_idx == I2C_LAST) begin
                        has_run <= 1'b1;
                        st      <= S_RPT_SEND;
                    end else begin
                        i2c_idx <= i2c_idx + 4'd1;
                        st      <= S_I2C_GO;
                    end
                end

                // ---------------- UART report ---------------------------
                S_RPT_SEND: begin
                    tx_data  <= msg_char(rpt_idx, ~spi_fail, ~i2c_fail);
                    tx_start <= 1'b1;
                    st       <= S_RPT_WAIT;
                end
                S_RPT_WAIT: if (tx_done) begin
                    if (rpt_idx == 5'd18) st <= S_IDLE;
                    else begin
                        rpt_idx <= rpt_idx + 5'd1;
                        st      <= S_RPT_SEND;
                    end
                end

                default: st <= S_IDLE;
            endcase
        end
    end

    //--------------------------------------------------------------------------
    // LEDs  (plain LEDs active-high, RGB LED active-low on Cmod A7)
    //--------------------------------------------------------------------------
    wire running = (st != S_IDLE);
    wire show    = has_run & ~running;
    wire c_red   = show & (spi_fail | i2c_fail);
    wire c_green = show & ~spi_fail & ~i2c_fail;
    wire c_blue  = running;

    assign led[0]  = show & ~spi_fail;
    assign led[1]  = show & ~i2c_fail;
    assign led0_r  = ~c_red;
    assign led0_g  = ~c_green;
    assign led0_b  = ~c_blue;
endmodule