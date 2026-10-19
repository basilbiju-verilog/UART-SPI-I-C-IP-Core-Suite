## =============================================================================
## Constraints for top_demo on Digilent Cmod A7-35T (XC7A35T-1CPG236C)
## Pin names follow Digilent's Cmod-A7-Master.xdc
## =============================================================================

## ---- 12 MHz system clock ----------------------------------------------------
set_property -dict { PACKAGE_PIN L17  IOSTANDARD LVCMOS33 } [get_ports clk]
create_clock -add -name sys_clk_pin -period 83.333 -waveform {0 41.667} [get_ports clk]

## ---- Buttons (active high): btn[0] = start test, btn[1] = reset -----------------
set_property -dict { PACKAGE_PIN A18  IOSTANDARD LVCMOS33 } [get_ports {btn[0]}]
set_property -dict { PACKAGE_PIN B18  IOSTANDARD LVCMOS33 } [get_ports {btn[1]}]

## ---- Plain LEDs (active high): LD1 = SPI pass, LD2 = I2C pass ------------------
set_property -dict { PACKAGE_PIN A17  IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN C16  IOSTANDARD LVCMOS33 } [get_ports {led[1]}]

## ---- RGB LED (active LOW): blue = running, green = PASS, red = FAIL ------------
set_property -dict { PACKAGE_PIN C17  IOSTANDARD LVCMOS33 } [get_ports led0_r]
set_property -dict { PACKAGE_PIN B16  IOSTANDARD LVCMOS33 } [get_ports led0_g]
set_property -dict { PACKAGE_PIN B17  IOSTANDARD LVCMOS33 } [get_ports led0_b]

## ---- USB-UART (FTDI) ----------------------------------------------------------
set_property -dict { PACKAGE_PIN J18  IOSTANDARD LVCMOS33 } [get_ports uart_rxd_out]   ;# FPGA TX -> PC
set_property -dict { PACKAGE_PIN J17  IOSTANDARD LVCMOS33 } [get_ports uart_txd_in]    ;# PC -> FPGA RX

## ---- Pmod JA : SPI loopback -----------------------------------------------------
## Top row   : JA pin1..4  = SPI MASTER side  (sclk, mosi, cs, miso-in)
## Bottom row: JA pin7..10 = SPI SLAVE  side  (sclk-in, mosi-in, cs-in, miso-out)
set_property -dict { PACKAGE_PIN G17  IOSTANDARD LVCMOS33 } [get_ports spi_sclk_o]   ;# JA pin 1
set_property -dict { PACKAGE_PIN G19  IOSTANDARD LVCMOS33 } [get_ports spi_mosi_o]   ;# JA pin 2
set_property -dict { PACKAGE_PIN N18  IOSTANDARD LVCMOS33 } [get_ports spi_cs_o]     ;# JA pin 3
set_property -dict { PACKAGE_PIN L18  IOSTANDARD LVCMOS33 } [get_ports spi_miso_i]   ;# JA pin 4
set_property -dict { PACKAGE_PIN H17  IOSTANDARD LVCMOS33 } [get_ports spi_sclk_i]   ;# JA pin 7
set_property -dict { PACKAGE_PIN H19  IOSTANDARD LVCMOS33 } [get_ports spi_mosi_i]   ;# JA pin 8
set_property -dict { PACKAGE_PIN J19  IOSTANDARD LVCMOS33 } [get_ports spi_cs_i]     ;# JA pin 9
set_property -dict { PACKAGE_PIN K18  IOSTANDARD LVCMOS33 } [get_ports spi_miso_o]   ;# JA pin 10

## ---- DIP header pins 1..4 : I2C loopback (open-drain, internal pull-ups) --------
## !! Double-check these 4 pins against Digilent's Cmod-A7-Master.xdc (pio[1]..pio[4]) !!
set_property -dict { PACKAGE_PIN M3   IOSTANDARD LVCMOS33 } [get_ports i2c_scl_m]    ;# pio[1]
set_property -dict { PACKAGE_PIN L3   IOSTANDARD LVCMOS33 } [get_ports i2c_sda_m]    ;# pio[2]
set_property -dict { PACKAGE_PIN A16  IOSTANDARD LVCMOS33 } [get_ports i2c_scl_s]    ;# pio[3]
set_property -dict { PACKAGE_PIN K3   IOSTANDARD LVCMOS33 } [get_ports i2c_sda_s]    ;# pio[4]

set_property PULLUP true [get_ports {i2c_scl_m i2c_sda_m i2c_scl_s i2c_sda_s}]

## ---- Timing: asynchronous human / external inputs --------------------------------
set_false_path -from [get_ports {btn[*] uart_txd_in}]

## ---- Configuration -------------------------------------------------------------
set_property CFGBVS VCCO        [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]