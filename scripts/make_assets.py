#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 iOS 工程需要的两个二进制资源（纯标准库，不依赖 Pillow / ffmpeg）：

  1) ArrAvid/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
     App 图标：橙红渐变背景 + 白色定位针，1024x1024（Xcode 14+ 单尺寸图标格式）

  2) ArrAvid/Resources/alarm.wav
     到站铃声：双音交替 + 颤音包络，44.1kHz 单声道 16bit，约 4 秒（通知声音上限 30 秒）

用法：python3 scripts/make_assets.py
"""

import math
import os
import struct
import wave
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON_PATH = os.path.join(ROOT, "ArrAvid/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
WAV_PATH = os.path.join(ROOT, "ArrAvid/Resources/alarm.wav")


# --------------------------------------------------------------------------
# PNG
# --------------------------------------------------------------------------

def write_png(path, width, height, rows):
    """rows: list of bytearray，每行 width*3 个 RGB 字节"""
    raw = b"".join(b"\x00" + bytes(r) for r in rows)

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", ihdr)
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)


def lerp(a, b, t):
    return a + (b - a) * t


def point_in_triangle(px, py, a, b, c):
    def sign(p1, p2, p3):
        return (p1[0] - p3[0]) * (p2[1] - p3[1]) - (p2[0] - p3[0]) * (p1[1] - p3[1])

    d1 = sign((px, py), a, b)
    d2 = sign((px, py), b, c)
    d3 = sign((px, py), c, a)
    has_neg = d1 < 0 or d2 < 0 or d3 < 0
    has_pos = d1 > 0 or d2 > 0 or d3 > 0
    return not (has_neg and has_pos)


def make_icon(path, size=1024, ss=2):
    """ss = 超采样倍数（抗锯齿）"""
    W = size * ss
    top = (250, 140, 40)      # 橙
    bottom = (207, 60, 20)    # 橙红

    # 定位针几何（按 1024 设计，再乘 ss）
    cx, cy, R = 512 * ss, 440 * ss, 300 * ss
    hole = 118 * ss
    tri = ((252 * ss, 620 * ss), (772 * ss, 620 * ss), (512 * ss, 900 * ss))

    rows = []
    for y in range(size):
        row = bytearray()
        for x in range(size):
            r = g = b = 0
            for sy in range(ss):
                for sx in range(ss):
                    px = x * ss + sx + 0.5
                    py = y * ss + sy + 0.5
                    t = py / W
                    br = lerp(top[0], bottom[0], t)
                    bg = lerp(top[1], bottom[1], t)
                    bb = lerp(top[2], bottom[2], t)

                    in_pin = ((px - cx) ** 2 + (py - cy) ** 2 <= R * R) or \
                             point_in_triangle(px, py, *tri)
                    if in_pin:
                        # 针身白色，中间挖一个圆形洞露出背景色
                        if (px - cx) ** 2 + (py - cy) ** 2 <= hole * hole:
                            br, bg, bb = br, bg, bb
                        else:
                            br, bg, bb = 255, 255, 255
                    r += br
                    g += bg
                    b += bb
            n = ss * ss
            row += bytes((int(r / n), int(g / n), int(b / n)))
        rows.append(row)

    write_png(path, size, size, rows)
    print("icon  ->", path)


# --------------------------------------------------------------------------
# WAV
# --------------------------------------------------------------------------

def make_alarm(path, sr=44100, duration=4.0):
    n = int(sr * duration)
    frames = bytearray()

    # 两段交替的双音，外加 6Hz 颤音，听起来像"到站了"的提示音
    segments = [
        (0.00, 0.30, 1000.0),
        (0.36, 0.30, 1000.0),
        (0.72, 0.55, 750.0),
        (1.32, 0.30, 1000.0),
        (1.68, 0.30, 1000.0),
        (2.04, 0.55, 750.0),
        (2.64, 0.30, 1000.0),
        (3.00, 0.30, 1000.0),
        (3.36, 0.60, 750.0),
    ]

    for i in range(n):
        t = i / sr
        value = 0.0
        for start, length, freq in segments:
            if start <= t < start + length:
                local = t - start
                # 起音 15ms、收音 40ms 的包络，避免爆音
                attack = min(1.0, local / 0.015)
                release = min(1.0, (length - local) / 0.040)
                env = min(attack, release)
                tremolo = 0.75 + 0.25 * math.sin(2 * math.pi * 6.0 * local)
                # 基频 + 一点二次谐波，更"尖锐"更容易吵醒人
                value = env * tremolo * (0.72 * math.sin(2 * math.pi * freq * local)
                                         + 0.28 * math.sin(2 * math.pi * freq * 2 * local))
                break
        sample = int(max(-1.0, min(1.0, value * 0.92)) * 32767)
        frames += struct.pack("<h", sample)

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(bytes(frames))
    print("sound ->", path, "(%.1fs)" % duration)


if __name__ == "__main__":
    make_icon(ICON_PATH)
    make_alarm(WAV_PATH)