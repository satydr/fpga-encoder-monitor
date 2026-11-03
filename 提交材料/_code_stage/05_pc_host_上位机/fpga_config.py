# -*- coding: utf-8 -*-
"""
fpga_config.py  --  FPGA 参数在线配置（经 UART 下发）

用途
====
FPGA 侧的报警阈值原来是编译期常量（``parameter integer SPEED_MAX = 700``），
烧进 bit 就固定了。改它必须重新综合、重新下载。

现在 FPGA 增加了接收通道（N5 脚），上位机可以发一条 6 字节的控制帧把它改掉，
**改完立刻生效，不用重新烧 bit**。

控制帧格式（上位机 -> FPGA）
=============================
=========  ======  ====================================================
字节      值      含义
=========  ======  ====================================================
[0]       0xAA    帧头 1（必须与 [1] 成对）
[1]       0x55    帧头 2
[2]       CMD     0x4E='N' 改超速阈值 / 0x50='P' 改丢脉冲容差
                   0x43='C' 清除两个报警（参数位填 0）
[3]       D_H     参数高字节
[4]       D_L     参数低字节
[5]       SUM     校验和 = CMD + D_H + D_L（低 8 位）
=========  ======  ====================================================

⚠️ 三条实测踩坑，务必遵守
==========================
1. **不要碰接收缓冲。** FPGA 每 10 ms 就在发数据帧，任何 read()/drain 都会
   把我们要发的时机搞乱。曾试"先 drain 再 write"，结果自己发的帧被后一次
   drain 吃掉，FPGA 根本没收到。→ 发送函数里**绝不**访问接收侧。

2. **命令要连发 3 次。** FPGA 与 PC 同时在发数据（115200，每 10 ms 一帧），
   单发一条 6 字节帧有概率被冲掉 —— 实测单发 20 次里只有 1~3 次生效。
   → ``REPEAT = 3``，间隔 10 ms，冗余足够且不占太多时间。

3. **清报警前必须先把阈值抬到转速之上。** 报警是**锁存**的，
   ``clr`` 只在收到命令那一拍有效；若此刻 rpm 仍大于阈值，
   同一拍 ``over_now`` 仍为真，报警立刻重新锁存 —— 清了等于没清。
   这是**设计意图**（报警要人工确认），不是 bug。
   → 正确用法：``set_speed_limit(ser, 900)`` 再 ``clear_alarm(ser)``。

典型用法
========
>>> from fpga_config import set_speed_limit, clear_alarm
>>> set_speed_limit(ser, 500)     # 阈值降到 500 -> 立刻报超速
>>> set_speed_limit(ser, 900)     # 先把阈值抬到转速之上
>>> clear_alarm(ser)              # 再清报警 -> 回到 0
"""

import time

FRAME_HEAD = bytes([0xAA, 0x55])

CMD_SPEED = 0x4E   # 'N'  改超速阈值
CMD_TOL   = 0x50   # 'P'  改丢脉冲容差
CMD_CLR   = 0x43   # 'C'  清报警

REPEAT = 3         # 连发次数（见文件头踩坑 2）


def build_frame(cmd, value=0):
    """拼一条 6 字节控制帧。cmd 取 CMD_*，value 为 16 位参数。"""
    dh = (value >> 8) & 0xFF
    dl = value & 0xFF
    s = (cmd + dh + dl) & 0xFF
    return bytes([0xAA, 0x55, cmd, dh, dl, s])


def _send(ser, cmd, value, label, verbose, repeat=REPEAT):
    """连发若干次一条控制帧。

    ⚠️ 只写不读 —— 见文件头踩坑 1。
    """
    frame = build_frame(cmd, value)
    for _ in range(repeat):
        ser.write(frame)
        try:
            ser.flush()
        except Exception:
            pass
        time.sleep(0.01)
    # 6 字节 ≈ 0.52 ms，留足余量让 FPGA 收完并执行
    time.sleep(0.05)
    if verbose:
        print("[cfg] %s -> %d   发送 %s x%d" % (label, value, frame.hex(" "), repeat))
    return frame


def set_speed_limit(ser, rpm_limit, verbose=True):
    """改超速阈值（转/分）。范围 0~65535，实际建议 50~25000。"""
    if not (0 <= int(rpm_limit) <= 0xFFFF):
        raise ValueError("超速阈值必须在 0~65535 之间，收到 %r" % (rpm_limit,))
    return _send(ser, CMD_SPEED, int(rpm_limit), "超速阈值", verbose)


def set_z_gap_tol(ser, tol, verbose=True):
    """改 Z 相周期容差（单位：计数）。2400 计数 = 1 圈。"""
    if not (0 <= int(tol) <= 0xFFFF):
        raise ValueError("容差必须在 0~65535 之间，收到 %r" % (tol,))
    return _send(ser, CMD_TOL, int(tol), "丢脉冲容差", verbose)


def clear_alarm(ser, verbose=True):
    """远程清除两个报警（等效于板上按 S0）。

    ⚠️ 若当前转速仍大于阈值，清完会立刻重新锁存（设计意图）。
       先用 set_speed_limit 把阈值抬上去再清。
    """
    return _send(ser, CMD_CLR, 0, "清报警", verbose)


def read_status(ser, seconds=1.0, port_label=""):
    """收一段时间的数据帧，返回 Counter{status: 帧数}。

    status 位含义：bit0=超速  bit1=丢脉冲  （即 {6'b0, pulse_loss, over_speed}）
    """
    from collections import Counter
    buf = bytearray()
    t_end = time.time() + seconds
    while time.time() < t_end:
        w = ser.in_waiting
        if w:
            buf += ser.read(w)
        else:
            time.sleep(0.008)
    sts = []
    i = 0
    while i + 11 <= len(buf):
        if buf[i] == 0xAA and buf[i+1] == 0x55:
            f = buf[i:i+11]
            if (sum(f[:10]) & 0xFF) == f[10]:
                sts.append(f[9])
            i += 11
        else:
            i += 1
    return Counter(sts)


def _interactive(port, baud):
    import serial as _s
    try:
        ser = _s.Serial(port, baud, timeout=0.2)
    except Exception as e:
        print("打不开 %s : %s" % (port, e))
        return 1
    print("FPGA 参数在线配置  端口 %s @ %d" % (port, baud))
    print("命令：")
    print("   speed <转/分>    改超速阈值")
    print("   tol   <计数>     改丢脉冲容差")
    print("   clr              清报警（若转速仍超阈值会立刻重新锁存）")
    print("   show             看最近 1 秒的 status 分布")
    print("   quit             退出\n")

    limit, tol = 700, 200
    while True:
        try:
            line = input("fpga> ").strip()
        except (EOFError, KeyboardInterrupt):
            print(); break
        if not line:
            continue
        parts = line.split()
        c = parts[0].lower()
        try:
            if c == "speed" and len(parts) >= 2:
                limit = int(parts[1]); set_speed_limit(ser, limit)
            elif c == "tol" and len(parts) >= 2:
                tol = int(parts[1]); set_z_gap_tol(ser, tol)
            elif c == "clr":
                clear_alarm(ser)
            elif c == "show":
                print("      status 分布：%s" % dict(read_status(ser, 1.0)))
                print("      （0=正常  1=超速  2=丢脉冲  3=两者都有）")
            elif c in ("quit", "exit", "q"):
                break
            else:
                print("      未知命令。")
        except ValueError as e:
            print("      参数错误：%s" % e)
        except Exception as e:
            print("      操作失败：%s" % e); break
    ser.close()
    return 0


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(
        description="FPGA 报警阈值在线配置（经 UART 下发，不用重新烧 bit）")
    ap.add_argument("-p", "--port", default="COM10")
    ap.add_argument("-b", "--baud", type=int, default=115200)
    ap.add_argument("--speed", type=int, help="设置超速阈值后退出")
    ap.add_argument("--tol", type=int, help="设置丢脉冲容差后退出")
    ap.add_argument("--clr", action="store_true", help="清报警后退出")
    ap.add_argument("--check", action="store_true", help="自检三项")
    a = ap.parse_args()

    if a.speed is None and a.tol is None and not a.clr and not a.check:
        raise SystemExit(_interactive(a.port, a.baud))

    import serial as _s
    try:
        ser = _s.Serial(a.port, a.baud, timeout=0.2)
    except Exception as e:
        raise SystemExit("打不开 %s : %s" % (a.port, e))

    if a.speed is not None:
        set_speed_limit(ser, a.speed)
    if a.tol is not None:
        set_z_gap_tol(ser, a.tol)
    if a.clr:
        clear_alarm(ser)

    if a.check:
        print("[自检] 基准：阈值 700（>自检源 600）+ 清报警 -> 应不报警")
        set_speed_limit(ser, 700, verbose=False)
        clear_alarm(ser, verbose=False)
        r = read_status(ser, 1.2)
        ok1 = r.get(0, 0) > 50 and 1 not in r
        print("        status = %s  %s" % (dict(r), "PASS" if ok1 else "FAIL"))

        print("[自检] 阈值压到 500（低于 600）-> 应报超速")
        set_speed_limit(ser, 500, verbose=False)
        r = read_status(ser, 1.2)
        ok2 = r.get(1, 0) > 50
        print("        status = %s  %s" % (dict(r), "PASS" if ok2 else "FAIL"))

        print("[自检] 抬回 700 再清报警 -> 应回到 0")
        set_speed_limit(ser, 700, verbose=False)
        clear_alarm(ser, verbose=False)
        time.sleep(0.6)
        read_status(ser, 0.5)        # 丢弃清报警前的残留帧
        r = read_status(ser, 1.5)    # 只统计稳定后的数据
        ok3 = r.get(0, 0) > 100 and r.get(1, 0) == 0
        print("        status = %s  %s" % (dict(r), "PASS" if ok3 else "FAIL"))

        set_speed_limit(ser, 700, verbose=False)
        clear_alarm(ser, verbose=False)

        if ok1 and ok2 and ok3:
            print("\n[自检] 全部通过 —— 阈值在线可改 + 远程清报警 工作正常")
        else:
            bad = [n for n, o in (("阈值高于转速时不报警", ok1),
                                  ("阈值低于转速时报超速", ok2),
                                  ("远程清报警生效", ok3)) if not o]
            print("\n[自检] 未通过：%s" % bad)
    ser.close()
