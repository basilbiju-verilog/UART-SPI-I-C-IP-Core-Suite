`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// tb_top_demo : self-checking testbench for top_demo (jumper wires modelled as nets)
//   1) sends 'A' over UART  -> expects "SPI:PASS I2C:PASS\r\n" back + green LED
//   2) presses BTN0         -> expects the same report again
// Run:  Vivado > Run Simulation > Run Behavioral Simulation (set tb_top_demo as sim top)
//       then "run all"  (or  run 15 ms)
//------------------------------------------------------------------------------
module tb_top_demo;
    localparam real CLK_PERIOD = 83.333;     // 12 MHz
    localparam real BIT_NS     = 8680.0;     // 115200 baud

    reg clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    reg  [1:0] btn         = 2'b00;
    reg        uart_txd_in = 1'b1;
    wire       uart_rxd_out;
    wire [1:0] led;
    wire       led0_r, led0_g, led0_b;

    // "jumper wires"
    wire spi_sclk, spi_mosi, spi_cs, spi_miso;
    tri1 i2c_scl, i2c_sda;                   // tri1 = pull-up resistor

    top_demo #(
        .AUTO_RUN(0),
        .DEBOUNCE_CYCLES(4)
    ) dut (
        .clk(clk), .btn(btn), .led(led),
        .led0_r(led0_r), .led0_g(led0_g), .led0_b(led0_b),
        .uart_txd_in(uart_txd_in), .uart_rxd_out(uart_rxd_out),
        .spi_sclk_o(spi_sclk), .spi_mosi_o(spi_mosi), .spi_cs_o(spi_cs), .spi_miso_i(spi_miso),
        .spi_sclk_i(spi_sclk), .spi_mosi_i(spi_mosi), .spi_cs_i(spi_cs), .spi_miso_o(spi_miso),
        .i2c_scl_m(i2c_scl), .i2c_sda_m(i2c_sda),
        .i2c_scl_s(i2c_scl), .i2c_sda_s(i2c_sda)
    );

    //--------------------------------------------------------------------------
    // UART monitor (captures what the FPGA sends to the PC)
    //--------------------------------------------------------------------------
    reg [7:0] rx_buf [0:63];
    integer   rx_n = 0;
    reg [7:0] rx_b;
    integer   k;

    initial begin
        forever begin
            @(negedge uart_rxd_out);
            #(BIT_NS * 1.5);
            for (k = 0; k < 8; k = k + 1) begin
                rx_b[k] = uart_rxd_out;
                #(BIT_NS);
            end
            rx_buf[rx_n] = rx_b;
            rx_n = rx_n + 1;
            if (rx_b >= 8'h20) $write("%c", rx_b);
            else if (rx_b == 8'h0A) $write("\n");
        end
    end

    //--------------------------------------------------------------------------
    // Helpers
    //--------------------------------------------------------------------------
    integer errors = 0;
    reg [8*17-1:0] exp_txt = "SPI:PASS I2C:PASS";

    task uart_send(input [7:0] b);
        integer i;
        begin
            uart_txd_in = 1'b0; #(BIT_NS);
            for (i = 0; i < 8; i = i + 1) begin
                uart_txd_in = b[i]; #(BIT_NS);
            end
            uart_txd_in = 1'b1; #(BIT_NS);
        end
    endtask

    task wait_chars(input integer n);          // wait until n chars were received (20 ms timeout)
        integer t;
        begin
            t = 0;
            while (rx_n < n && t < 20000) begin #1000; t = t + 1; end
            if (rx_n < n) begin
                $display("[TB] ERROR: timeout, only %0d chars received", rx_n);
                errors = errors + 1;
            end
        end
    endtask

    task check_msg(input integer base);
        integer i;
        integer e;
        begin
            e = 0;
            for (i = 0; i < 17; i = i + 1)
                if (rx_buf[base + i] !== exp_txt[8*(16 - i) +: 8]) e = e + 1;
            if (rx_buf[base + 17] !== 8'h0D || rx_buf[base + 18] !== 8'h0A) e = e + 1;
            if (e == 0) $display("[TB] report at offset %0d : OK", base);
            else begin
                $display("[TB] report at offset %0d : MISMATCH (%0d chars wrong)", base, e);
                errors = errors + 1;
            end
        end
    endtask

    task check_leds_pass;
        begin
            if (led !== 2'b11 || led0_g !== 1'b0 || led0_r !== 1'b1 || led0_b !== 1'b1) begin
                $display("[TB] ERROR: LEDs wrong: led=%b rgb(r,g,b)=%b%b%b", led, led0_r, led0_g, led0_b);
                errors = errors + 1;
            end else
                $display("[TB] LEDs show PASS (LD1+LD2 on, RGB green)");
        end
    endtask

    //--------------------------------------------------------------------------
    // Main stimulus
    //--------------------------------------------------------------------------
    initial begin
        $display("[TB] start");
        #100_000;                               // power-on reset

        $display("[TB] --- run 1: trigger by UART byte 'A' ---");
        uart_send("A");
        wait_chars(19);
        #(BIT_NS * 2);
        check_msg(0);
        check_leds_pass;

        #200_000;
        $display("[TB] --- run 2: trigger by BTN0 ---");
        btn[0] = 1'b1;
        #(CLK_PERIOD * 20);
        btn[0] = 1'b0;
        wait_chars(38);
        #(BIT_NS * 2);
        check_msg(19);
        check_leds_pass;

        if (errors == 0) $display("[TB] *** ALL TESTS PASSED ***");
        else             $display("[TB] *** %0d ERROR(S) ***", errors);
        $finish;
    end
endmodule