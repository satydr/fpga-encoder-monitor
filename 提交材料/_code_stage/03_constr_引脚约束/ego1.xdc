# =============================================================================
#  ego1.xdc  --  EGO1 开发板引脚约束（XC7A35T-1CSG324C）
#  依据：EGo1 用户手册 v1.1
#  ⚠️ 数码管共阴、段选与位选都是高电平有效
# =============================================================================

set_property CFGBVS VCCO        [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

# ---------------------------------------------------------------- 系统时钟 100 MHz
set_property -dict {PACKAGE_PIN P17   IOSTANDARD LVCMOS33} [get_ports sys_clk]
create_clock -period 10.000 -name sys_clk [get_ports sys_clk]

# ---------------------------------------------------------------- 复位键 / 清除键
set_property -dict {PACKAGE_PIN P15   IOSTANDARD LVCMOS33} [get_ports rst_btn]   ;# FPGA_RESET
set_property -dict {PACKAGE_PIN R11   IOSTANDARD LVCMOS33} [get_ports clr_btn]   ;# S0

# ---------------------------------------------------------------- 拨码开关 SW0~SW7
set_property -dict {PACKAGE_PIN P5    IOSTANDARD LVCMOS33} [get_ports {sw[0]}]
set_property -dict {PACKAGE_PIN P4    IOSTANDARD LVCMOS33} [get_ports {sw[1]}]
set_property -dict {PACKAGE_PIN P3    IOSTANDARD LVCMOS33} [get_ports {sw[2]}]
set_property -dict {PACKAGE_PIN P2    IOSTANDARD LVCMOS33} [get_ports {sw[3]}]
set_property -dict {PACKAGE_PIN R2    IOSTANDARD LVCMOS33} [get_ports {sw[4]}]
set_property -dict {PACKAGE_PIN M4    IOSTANDARD LVCMOS33} [get_ports {sw[5]}]
set_property -dict {PACKAGE_PIN N4    IOSTANDARD LVCMOS33} [get_ports {sw[6]}]
set_property -dict {PACKAGE_PIN R1    IOSTANDARD LVCMOS33} [get_ports {sw[7]}]

# ---------------------------------------------------------------- 编码器输入（J5）
# ⚠️ 编码器是集电极开路输出，外部必须 4.7 kΩ 上拉到 3.3 V（绝不能 5 V）
# ⚠️ 编码器用独立 12 V 供电，但与 FPGA 必须共地
set_property -dict {PACKAGE_PIN B11   IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports enc_a]   ;# J5-15
set_property -dict {PACKAGE_PIN A11   IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports enc_b]   ;# J5-16
set_property -dict {PACKAGE_PIN E15   IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports enc_z]   ;# J5-17

# ---------------------------------------------------------------- OLED（I2C，J5 扩展口）
# OLED 模块自带 4.7 kΩ 上拉，这里不再开 FPGA 内部上拉；若模块没带再补 PULLUP TRUE
set_property -dict {PACKAGE_PIN E16   IOSTANDARD LVCMOS33} [get_ports oled_scl]   ;# J5-18
set_property -dict {PACKAGE_PIN D15   IOSTANDARD LVCMOS33} [get_ports oled_sda]   ;# J5-19

# ---------------------------------------------------------------- LED0~LED15（高电平点亮）
set_property -dict {PACKAGE_PIN F6    IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN G4    IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN G3    IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN J4    IOSTANDARD LVCMOS33} [get_ports {led[3]}]
set_property -dict {PACKAGE_PIN H4    IOSTANDARD LVCMOS33} [get_ports {led[4]}]
set_property -dict {PACKAGE_PIN J3    IOSTANDARD LVCMOS33} [get_ports {led[5]}]
set_property -dict {PACKAGE_PIN J2    IOSTANDARD LVCMOS33} [get_ports {led[6]}]
set_property -dict {PACKAGE_PIN K2    IOSTANDARD LVCMOS33} [get_ports {led[7]}]
set_property -dict {PACKAGE_PIN K1    IOSTANDARD LVCMOS33} [get_ports {led[8]}]
set_property -dict {PACKAGE_PIN H6    IOSTANDARD LVCMOS33} [get_ports {led[9]}]
set_property -dict {PACKAGE_PIN H5    IOSTANDARD LVCMOS33} [get_ports {led[10]}]
set_property -dict {PACKAGE_PIN J5    IOSTANDARD LVCMOS33} [get_ports {led[11]}]
set_property -dict {PACKAGE_PIN K6    IOSTANDARD LVCMOS33} [get_ports {led[12]}]
set_property -dict {PACKAGE_PIN L1    IOSTANDARD LVCMOS33} [get_ports {led[13]}]
set_property -dict {PACKAGE_PIN M1    IOSTANDARD LVCMOS33} [get_ports {led[14]}]
set_property -dict {PACKAGE_PIN K3    IOSTANDARD LVCMOS33} [get_ports {led[15]}]

# ---------------------------------------------------------------- 数码管组0（DN0）段 A~DP
set_property -dict {PACKAGE_PIN B4    IOSTANDARD LVCMOS33} [get_ports {seg0[0]}]   ;# A0
set_property -dict {PACKAGE_PIN A4    IOSTANDARD LVCMOS33} [get_ports {seg0[1]}]   ;# B0
set_property -dict {PACKAGE_PIN A3    IOSTANDARD LVCMOS33} [get_ports {seg0[2]}]   ;# C0
set_property -dict {PACKAGE_PIN B1    IOSTANDARD LVCMOS33} [get_ports {seg0[3]}]   ;# D0
set_property -dict {PACKAGE_PIN A1    IOSTANDARD LVCMOS33} [get_ports {seg0[4]}]   ;# E0
set_property -dict {PACKAGE_PIN B3    IOSTANDARD LVCMOS33} [get_ports {seg0[5]}]   ;# F0
set_property -dict {PACKAGE_PIN B2    IOSTANDARD LVCMOS33} [get_ports {seg0[6]}]   ;# G0
set_property -dict {PACKAGE_PIN D5    IOSTANDARD LVCMOS33} [get_ports {seg0[7]}]   ;# DP0

# ---------------------------------------------------------------- 数码管组0 位选 K1~K4
set_property -dict {PACKAGE_PIN G2    IOSTANDARD LVCMOS33} [get_ports {dig0[0]}]   ;# DN0_K1
set_property -dict {PACKAGE_PIN C2    IOSTANDARD LVCMOS33} [get_ports {dig0[1]}]   ;# DN0_K2
set_property -dict {PACKAGE_PIN C1    IOSTANDARD LVCMOS33} [get_ports {dig0[2]}]   ;# DN0_K3
set_property -dict {PACKAGE_PIN H1    IOSTANDARD LVCMOS33} [get_ports {dig0[3]}]   ;# DN0_K4

# ---------------------------------------------------------------- 数码管组1（DN1）段 A~DP
set_property -dict {PACKAGE_PIN D4    IOSTANDARD LVCMOS33} [get_ports {seg1[0]}]   ;# A1
set_property -dict {PACKAGE_PIN E3    IOSTANDARD LVCMOS33} [get_ports {seg1[1]}]   ;# B1
set_property -dict {PACKAGE_PIN D3    IOSTANDARD LVCMOS33} [get_ports {seg1[2]}]   ;# C1
set_property -dict {PACKAGE_PIN F4    IOSTANDARD LVCMOS33} [get_ports {seg1[3]}]   ;# D1
set_property -dict {PACKAGE_PIN F3    IOSTANDARD LVCMOS33} [get_ports {seg1[4]}]   ;# E1
set_property -dict {PACKAGE_PIN E2    IOSTANDARD LVCMOS33} [get_ports {seg1[5]}]   ;# F1
set_property -dict {PACKAGE_PIN D2    IOSTANDARD LVCMOS33} [get_ports {seg1[6]}]   ;# G1
set_property -dict {PACKAGE_PIN H2    IOSTANDARD LVCMOS33} [get_ports {seg1[7]}]   ;# DP1

# ---------------------------------------------------------------- 数码管组1 位选 K1~K4
set_property -dict {PACKAGE_PIN G1    IOSTANDARD LVCMOS33} [get_ports {dig1[0]}]   ;# DN1_K1
set_property -dict {PACKAGE_PIN F1    IOSTANDARD LVCMOS33} [get_ports {dig1[1]}]   ;# DN1_K2
set_property -dict {PACKAGE_PIN E1    IOSTANDARD LVCMOS33} [get_ports {dig1[2]}]   ;# DN1_K3
set_property -dict {PACKAGE_PIN G6    IOSTANDARD LVCMOS33} [get_ports {dig1[3]}]   ;# DN1_K4

# ---------------------------------------------------------------- UART 发送（板载 CP2102）
set_property -dict {PACKAGE_PIN T4    IOSTANDARD LVCMOS33 DRIVE 8} [get_ports uart_tx]
# UART 接收端：N5 = 手册里的 UART_TX = FPGA 的接收端，与 T4 成对
set_property -dict {PACKAGE_PIN N5    IOSTANDARD LVCMOS33} [get_ports uart_rx]

# ---------------------------------------------------------------- 慢速/异步口不做端口时序约束
set_false_path -from [get_ports {sw[*]}]
set_false_path -from [get_ports {rst_btn clr_btn}]
set_false_path -from [get_ports {enc_a enc_b enc_z}]
set_false_path -to   [get_ports {led[*]}]
set_false_path -to   [get_ports {seg0[*] seg1[*] dig0[*] dig1[*]}]
set_false_path -to   [get_ports uart_tx]
# uart_rx 是输入端口，false_path 必须用 -from（不是 -to）
set_false_path -from [get_ports uart_rx]
set_false_path -to   [get_ports {oled_scl oled_sda}]
set_false_path -from [get_ports oled_sda]
