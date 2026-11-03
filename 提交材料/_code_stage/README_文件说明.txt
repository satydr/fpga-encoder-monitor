FPGA 运动编码器在线状态监测系统
重要代码包（全国大学生嵌入式芯片与系统设计竞赛 FPGA 创新设计赛道）

【作品信息】
  组号：51528
  赛题：A 题
  平台：EGO1（Xilinx Artix-7 XC7A35T-1CSG324C）
  工具：Vivado 2026.1，纯 Verilog HDL（无软核、无 SDK、无外部 MCU）
  成员：胡毅（25019100600）、贺宇翔（25019100088）、杨海涛（25019100022）

【目录说明】
  01_rtl_设计源码        16 个 RTL 模块（同步/消抖/解码/位置/测速/滤波/报警/
                         UART/I2C/OLED/数码管/顶层）
  02_sim_测试台          17 个 testbench（单元 → 分层集成 → 板级整链）
  03_constr_引脚约束     ego1.xdc
  04_bitstream_烧录文件  board_top_oled.bit（脱机演示需另烧 .bin 到 SPI Flash）
  05_pc_host_上位机      uart_monitor.py（收数绘图）+ fpga_config.py（阈值下发）

【快速复现】
  1. Vivado 打开 vivadoprj/vivadoprj.xpr（工程文件路径需与本机一致，或新建工程后
     按 01/02/03 目录加入文件）
  2. 综合 → 实现 → 生成比特流
  3. 烧写 04 目录中的 bit；脱机演示请把 .bin 烧入 SPI Flash 并将 JP2 跳到 QSPI
  4. PC 端：python uart_monitor.py -p COMx -b 115200

【工程规模】
  设计源 16 个 · 测试台 17 个 · 约束 1 个 · LUT 占用 2.09% · 主时钟 100 MHz
  实测最高 576 转/分（受电机额定限制），仿真标定上限 25000 转/分

打包时间：2026-11-03 15:59
