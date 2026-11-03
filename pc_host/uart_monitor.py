#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
=============================================================================
 uart_monitor.py  ——  FPGA 编码器在线监测 · PC 上位机
=============================================================================
 配套：E:\\project\\vivadoprj  （EGO1 / XC7A35T）
 链路：encoder_top -> uart_frame -> uart_tx -> T4 -> CP2102/FT2232 -> USB -> COMx

 ---- 帧格式（与 uart_frame.v 严格一致，11 字节定长，多字节字段大端）----
   [0]  0xAA              帧头 1
   [1]  0x55              帧头 2
   [2]  0x07              数据段长度（固定 7）
   [3]  turns[15:8]       圈数（有符号 16）高字节
   [4]  turns[7:0]        圈数 低字节
   [5]  {4'b0, pos[11:8]} 圈内位置 高字节（高 4 位补 0）
   [6]  pos[7:0]          圈内位置 低字节
   [7]  rpm[15:8]         滤波后转速 高字节
   [8]  rpm[7:0]          滤波后转速 低字节
   [9]  {6'b0, pulse_loss, over_speed}   状态字节  (bit1=丢脉冲 bit0=超速)
   [10] SUM               前 10 字节累加和的低 8 位

 上位机侧换算：  绝对位置 = turns * 2400 + position      (2400 = 600PPR x 4 倍频)

 ---- 用法 ----
   python uart_monitor.py --selftest          # 自检：不接板子，用仿真抓到的真实帧验证解析
   python uart_monitor.py --list              # 列出本机可用串口
   python uart_monitor.py -p COM10            # 实时接收 + 画曲线（默认 115200）
   python uart_monitor.py -p COM10 --dump     # 只打印原始十六进制，不画图
   python uart_monitor.py -p COM10 --csv log.csv   # 同时存 CSV

 依赖： pyserial（必需）   matplotlib（可选，画图时才需要）
=============================================================================
"""

import sys
import os
import time
import argparse
import struct

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    serial = None

# ---------------------------------------------------------------- 常量
HDR1     = 0xAA
HDR2     = 0x55
DATA_LEN = 0x07
FRAME_N  = 11                 # 一帧总字节数
CPR      = 2400               # 每圈的四倍频计数（600 PPR x 4）

ST_OVER_SPEED = 0x01
ST_PULSE_LOSS = 0x02


# ============================================================================
#  帧解析器
#  设计要点：这是一个"流式"解析器 —— 不假设收到的第一个字节就是帧头。
#  真实串口上电时往往是从半帧开始的（板子早已在发，PC 是中途打开的），
#  所以必须先找 AA 55 同步，找不到就丢一个字节继续找。
# ============================================================================
class FrameParser:
    def __init__(self):
        self.buf = bytearray()
        self.frames_ok = 0
        self.bytes_drop = 0
        self.bad_sum = 0

    def feed(self, data):
        """喂入任意长度的字节流，返回解析出的完整帧列表"""
        self.buf.extend(data)
        out = []
        while True:
            idx = self._find_header()
            if idx < 0:
                # 缓冲区里连一个完整帧头都没有 -> 只保留最后一个可能是 0xAA 的字节
                if self.buf and self.buf[-1] == HDR1:
                    self.bytes_drop += len(self.buf) - 1
                    self.buf = self.buf[-1:]
                else:
                    self.bytes_drop += len(self.buf)
                    self.buf.clear()
                break
            if idx > 0:                       # 帧头前面有垃圾字节，丢掉
                self.bytes_drop += idx
                del self.buf[:idx]
            if len(self.buf) < FRAME_N:       # 还没收满，等下一批
                break
            frame = bytes(self.buf[:FRAME_N])
            f = self._decode(frame)
            if f is not None:
                del self.buf[:FRAME_N]        # 只有真帧才整帧消费
                self.frames_ok += 1
                out.append(f)
            else:
                # ⚠️ 关键：校验和/长度不对时**只丢 1 个字节**再重新同步，
                #    绝不能整帧丢掉 —— 否则会把紧跟其后的那一帧的真字节一起吞掉。
                #    （PC 中途打开串口、或串口丢了几个字节时，这个坑必然触发）
                self.bytes_drop += 1
                del self.buf[:1]
        return out

    def _find_header(self):
        for i in range(len(self.buf) - 1):
            if self.buf[i] == HDR1 and self.buf[i + 1] == HDR2:
                return i
        return -1

    def _decode(self, b):
        """把 11 字节解成 dict；校验和不对返回 None"""
        if len(b) != FRAME_N:
            return None
        if b[2] != DATA_LEN:                  # 长度字段不对 -> 假同步，返回 None 触发逐字节重同步
            return None
        calc = sum(b[:10]) & 0xFF
        if calc != b[10]:
            self.bad_sum += 1
            return None

        turns = struct.unpack(">h", b[3:5])[0]        # 有符号 16 位，大端
        pos   = ((b[5] & 0x0F) << 8) | b[6]           # 12 位圈内位置
        rpm   = (b[7] << 8) | b[8]
        st    = b[9]

        return {
            "raw"     : b.hex(" "),
            "turns"   : turns,
            "pos"     : pos,
            "abs_pos" : turns * CPR + pos,
            "rpm"     : rpm,
            "over"    : bool(st & ST_OVER_SPEED),
            "loss"    : bool(st & ST_PULSE_LOSS),
            "sum_ok"  : True,
        }


# ============================================================================
#  自检：用"仿真里真实抓到的帧"验证解析器，不需要板子
# ============================================================================
# 下面 4 帧全部来自 tb_uart_frame.v / tb_top_uart.v 的实测输出，不是我编的
SELFTEST_FRAMES = [
    # (字节流, 期望 turns, 期望 pos, 期望 rpm, 期望 status)
    ("aa 55 07 ff fd 04 d2 02 58 01 33", -3, 1234, 600, 0x01),
    ("aa 55 07 00 05 00 07 01 c2 02 d7",  5,    7, 450, 0x02),
    ("aa 55 07 00 00 00 f0 00 96 00 8c",  0,  240, 150, 0x00),
    ("aa 55 07 00 00 01 e0 01 2c 00 14",  0,  480, 300, 0x00),
]

# 额外的鲁棒性用例：帧头前有垃圾、半帧、校验和错
NOISE_PREFIX = "de ad be ef "          # 垃圾前缀：考验重新同步
HALF_FRAME   = "aa 55 07 00"           # 半帧：考验"等下一批"
BAD_SUM      = "aa 55 07 00 00 00 00 00 00 00 99"   # 校验和故意错：应被丢弃


def selftest():
    print("=" * 68)
    print(" SELFTEST  (no board required)")
    print("=" * 68)
    ok = True
    tot_ok = tot_drop = tot_bad = 0

    # --- 用例 1~4：帧头前塞垃圾 + 半帧，验证能否正确重新同步 ---
    # 每个用例用**独立的**解析器，统计才干净
    for i, (hexs, et, ep, er, es) in enumerate(SELFTEST_FRAMES, 1):
        p = FrameParser()
        stream = bytes.fromhex(NOISE_PREFIX + HALF_FRAME.replace(" ", "") + hexs.replace(" ", ""))
        frames = p.feed(stream)
        tot_ok += p.frames_ok; tot_drop += p.bytes_drop; tot_bad += p.bad_sum
        if len(frames) != 1:
            print("  TP%d : FAIL  expected 1 frame, got %d" % (i, len(frames)))
            ok = False
            continue
        f = frames[0]
        good = (f["turns"] == et and f["pos"] == ep and f["rpm"] == er
                and ((f["over"] and es & 1) or (not f["over"] and not es & 1))
                and ((f["loss"] and es & 2) or (not f["loss"] and not es & 2)))
        print("  TP%d : %s  turns=%-5d pos=%-5d rpm=%-4d over=%d loss=%d   (exp %d/%d/%d)"
              % (i, "PASS" if good else "FAIL", f["turns"], f["pos"], f["rpm"],
                 f["over"], f["loss"], et, ep, er))
        if not good:
            ok = False

    # --- 用例 5：校验和错 -> 必须被丢掉，不能输出 ---
    p5 = FrameParser()
    frames = p5.feed(bytes.fromhex(BAD_SUM.replace(" ", "")))
    r5 = (len(frames) == 0 and p5.bad_sum == 1)
    print("  TP5 : %s  bad-checksum frame rejected (bad_sum=%d)" % ("PASS" if r5 else "FAIL", p5.bad_sum))
    ok = ok and r5
    tot_ok += p5.frames_ok; tot_drop += p5.bytes_drop; tot_bad += p5.bad_sum

    # --- 用例 6：一帧被拆成两次到达（串口上很常见） ---
    p2 = FrameParser()
    f6 = bytes.fromhex(SELFTEST_FRAMES[0][0].replace(" ", ""))
    a = p2.feed(f6[:5])
    b = p2.feed(f6[5:])
    r6 = (len(a) == 0 and len(b) == 1 and b[0]["rpm"] == 600)
    print("  TP6 : %s  frame split across two reads" % ("PASS" if r6 else "FAIL"))
    ok = ok and r6
    tot_ok += p2.frames_ok; tot_drop += p2.bytes_drop; tot_bad += p2.bad_sum

    # --- 用例 7：绝对位置换算 ---
    f7 = FrameParser().feed(bytes.fromhex(SELFTEST_FRAMES[0][0].replace(" ", "")))[0]
    exp_abs = -3 * CPR + 1234
    r7 = f7["abs_pos"] == exp_abs
    print("  TP7 : %s  abs_pos = turns*%d + pos = %d" % ("PASS" if r7 else "FAIL", CPR, f7["abs_pos"]))
    ok = ok and r7

    print("-" * 68)
    print("  parser stats : frames_ok=%d  bytes_dropped=%d  bad_sum=%d"
          % (tot_ok, tot_drop, tot_bad))
    print("  RESULT       : %s" % ("ALL PASS" if ok else "*** FAILED ***"))
    print("=" * 68)
    return 0 if ok else 1


# ============================================================================
#  串口实时接收
# ============================================================================
def list_ports():
    if serial is None:
        print("pyserial not installed ->  pip install pyserial")
        return 1
    ports = list(serial.tools.list_ports.comports())
    if not ports:
        print("No serial port found.")
        return 1
    print("%-10s %-40s %s" % ("PORT", "DESCRIPTION", "HWID"))
    print("-" * 90)
    for p in ports:
        print("%-10s %-40s %s" % (p.device, (p.description or "")[:40], p.hwid))
    return 0


def run_live(port, baud, dump=False, csv_path=None, max_pts=600, plot=True):
    if serial is None:
        print("pyserial not installed ->  pip install pyserial")
        return 1

    try:
        ser = serial.Serial(port, baud, timeout=0.2)
    except Exception as e:
        print("Cannot open %s : %s" % (port, e))
        return 1
    print("Opened %s @ %d bps.  Ctrl+C to stop." % (port, baud))

    parser = FrameParser()
    fh = None
    if csv_path:
        fh = open(csv_path, "w", newline="")
        fh.write("t_sec,turns,pos,abs_pos,rpm,over_speed,pulse_loss\n")

    t0 = time.time()
    last_report = 0.0
    ts, rpms, abss = [], [], []
    alarms = []

    # 画图（可选）
    fig = ax = line = None
    if plot and not dump:
        try:
            import matplotlib
            try:
                matplotlib.use("TkAgg")
            except Exception:
                pass
            import matplotlib.pyplot as plt
            plt.ion()
            fig, (ax, ax2) = plt.subplots(2, 1, figsize=(10, 6), sharex=True)
            line, = ax.plot([], [], "-", color="#d62728", lw=1.5, label="rpm (filtered)")
            ax.set_ylabel("rpm")
            ax.set_title("FPGA Encoder Monitor   %s @ %d" % (port, baud))
            ax.grid(alpha=.3); ax.legend(loc="upper right")
            line2, = ax2.plot([], [], "-", color="#1f77b4", lw=1.5, label="abs position")
            ax2.set_ylabel("counts"); ax2.set_xlabel("time (s)")
            ax2.grid(alpha=.3); ax2.legend(loc="upper right")
            plt.tight_layout()
        except Exception as e:
            print("matplotlib unavailable (%s) -> fall back to text mode" % e)
            fig = None

    try:
        while True:
            data = ser.read(4096)
            if not data:
                if fig:
                    plt.pause(0.01)
                continue
            if dump:
                print(data.hex(" "))
            frames = parser.feed(data)
            for f in frames:
                t = time.time() - t0
                ts.append(t); rpms.append(f["rpm"]); abss.append(f["abs_pos"])
                if len(ts) > max_pts:
                    ts.pop(0); rpms.pop(0); abss.pop(0)
                if f["over"] or f["loss"]:
                    alarms.append((t, f["rpm"], f["over"], f["loss"]))
                if fh:
                    fh.write("%.3f,%d,%d,%d,%d,%d,%d\n" %
                             (t, f["turns"], f["pos"], f["abs_pos"], f["rpm"],
                              int(f["over"]), int(f["loss"])))
                # 每 0.5 s 打印一行，避免刷屏
                if t - last_report >= 0.5:
                    last_report = t
                    flag = ("  <<< OVERSPEED" if f["over"] else "") + \
                           ("  <<< PULSE LOSS" if f["loss"] else "")
                    print("t=%7.2fs  turns=%6d  pos=%5d  abs=%10d  rpm=%5d%s"
                          % (t, f["turns"], f["pos"], f["abs_pos"], f["rpm"], flag))
                    if fh:
                        fh.flush()

            if fig and frames:
                line.set_data(ts, rpms)
                ax.relim(); ax.autoscale_view()
                line2.set_data(ts, abss)
                ax2.relim(); ax2.autoscale_view()
                for a in alarms:
                    ax.axvline(a[0], color="orange", alpha=.4, lw=1)
                alarms.clear()
                plt.pause(0.001)

    except KeyboardInterrupt:
        print("\nStopped.")
    finally:
        ser.close()
        if fh:
            fh.close()
            print("CSV saved -> %s" % csv_path)
        print("frames_ok=%d  bytes_dropped=%d  bad_sum=%d"
              % (parser.frames_ok, parser.bytes_drop, parser.bad_sum))
    return 0


# ============================================================================
#  演练模式：不接板子，本地造 N 帧数据，验证"解析 -> 打印 -> 存 CSV -> 画图"整条链路
#  用途：在上位机脚本阶段就能把除"真实串口"以外的所有代码跑通
# ============================================================================
def make_frame(turns, pos, rpm, over=False, loss=False):
    """按 uart_frame.v 的格式造一帧（含正确的校验和）"""
    st = (0x02 if loss else 0) | (0x01 if over else 0)
    b = bytes([HDR1, HDR2, DATA_LEN,
               (turns >> 8) & 0xFF, turns & 0xFF,
               (pos >> 8) & 0x0F, pos & 0xFF,
               (rpm >> 8) & 0xFF, rpm & 0xFF,
               st, 0x00])
    b = b[:10] + bytes([sum(b[:10]) & 0xFF])
    return b


def run_sim(n=200, csv_path=None, plot=True):
    print("=" * 68)
    print(" SIM MODE  (no board): generating %d synthetic frames" % n)
    print("=" * 68)
    parser = FrameParser()
    stream = bytearray()
    for i in range(n):
        rpm = 0 if i < 20 else min(600, (i - 20) * 4)      # 前 2 s 静止，之后爬坡到 600
        rpm = rpm + (i % 5) - 2 if rpm > 0 else 0           # 叠一点抖动
        over = rpm > 500
        loss = (i % 97 == 0) and i > 30
        stream += make_frame(i // 24, (i * 7) % CPR, rpm, over, loss)

    frames = parser.feed(bytes(stream))
    print("  fed %d bytes -> parsed %d frames  (bad_sum=%d)"
          % (len(stream), len(frames), parser.bad_sum))
    if not frames:
        print("  *** no frame parsed ***")
        return 1

    first, last = frames[0], frames[-1]
    print("  first : rpm=%-4d pos=%-5d turns=%d" % (first["rpm"], first["pos"], first["turns"]))
    print("  last  : rpm=%-4d pos=%-5d turns=%d" % (last["rpm"], last["pos"], last["turns"]))
    n_over = sum(1 for f in frames if f["over"])
    n_loss = sum(1 for f in frames if f["loss"])
    print("  alarms: overspeed=%d frames, pulse_loss=%d frames" % (n_over, n_loss))

    if csv_path:
        with open(csv_path, "w", newline="") as fh:
            fh.write("t_sec,turns,pos,abs_pos,rpm,over_speed,pulse_loss\n")
            for i, f in enumerate(frames):
                fh.write("%.3f,%d,%d,%d,%d,%d,%d\n" %
                         (i * 0.01, f["turns"], f["pos"], f["abs_pos"], f["rpm"],
                          int(f["over"]), int(f["loss"])))
        print("  CSV saved -> %s" % csv_path)

    if plot:
        try:
            import matplotlib
            try:
                matplotlib.use("TkAgg")
            except Exception:
                pass
            import matplotlib.pyplot as plt
            ts = [i * 0.01 for i in range(len(frames))]
            rpms = [f["rpm"] for f in frames]
            abss = [f["abs_pos"] for f in frames]
            fig, (ax, ax2) = plt.subplots(2, 1, figsize=(10, 6), sharex=True)
            ax.plot(ts, rpms, color="#d62728", lw=1.5, label="rpm (filtered)")
            ax.set_ylabel("rpm"); ax.set_title("SIM: rpm ramp (no board)")
            ax.grid(alpha=.3); ax.legend(loc="upper right")
            ax2.plot(ts, abss, color="#1f77b4", lw=1.5, label="abs position")
            ax2.set_ylabel("counts"); ax2.set_xlabel("time (s)")
            ax2.grid(alpha=.3); ax2.legend(loc="upper right")
            plt.tight_layout()
            plt.show()
        except Exception as e:
            print("  (plot skipped: %s)" % e)

    ok = (parser.bad_sum == 0 and len(frames) == n and n_over > 0)
    print("-" * 68)
    print("  RESULT : %s" % ("ALL PASS" if ok else "*** FAILED ***"))
    print("=" * 68)
    return 0 if ok else 1


# ============================================================================
def main():
    ap = argparse.ArgumentParser(description="FPGA encoder monitor (PC host)")
    ap.add_argument("-p", "--port", help="serial port, e.g. COM10")
    ap.add_argument("-b", "--baud", type=int, default=115200)
    ap.add_argument("--list", action="store_true", help="list available serial ports")
    ap.add_argument("--selftest", action="store_true", help="verify parser using frames captured from simulation")
    ap.add_argument("--sim", type=int, nargs="?", const=200, metavar="N",
                    help="generate N synthetic frames and run the full pipeline (no board)")
    ap.add_argument("--dump", action="store_true", help="print raw hex only")
    ap.add_argument("--csv", help="also write samples to CSV")
    ap.add_argument("--no-plot", action="store_true", help="text mode only")
    a = ap.parse_args()

    if a.selftest:
        return selftest()
    if a.sim:
        return run_sim(a.sim, a.csv, plot=not a.no_plot)
    if a.list:
        return list_ports()
    if not a.port:
        ap.print_help()
        print("\nTip: run  --selftest  first (no board needed), then  --list  to find the COM port.")
        return 1
    return run_live(a.port, a.baud, a.dump, a.csv, plot=not a.no_plot)


if __name__ == "__main__":
    sys.exit(main())
