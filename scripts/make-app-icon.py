#!/usr/bin/env python3
"""
MagPulse macOS AppIcon Generator
Follows ReffWu family macOS AppIcon specifications (Stoop / TokNotch standard).
Generates master 2048x2048 icon, standard macOS squircle with engraved rim,
and builds AppIcon.icns via iconutil.
"""

import json
import math
import os
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "Resources"
ICONSET = ROOT / "icon.iconset"
OUTPUT_ICNS = RESOURCES / "AppIcon.icns"

NAME = "MAGPULSE"
SIGNATURE = "REFFWU"
FONT_PATH = "/System/Library/Fonts/Optima.ttc"
FONT_SIZE = 125
TRACKING = 26
SIZE = 2048
SCALE = 2

INNER = (176, 176, 1872, 1872)
INNER_RADIUS = 392
FRAME = 132
OUTER = (INNER[0] - FRAME, INNER[1] - FRAME, INNER[2] + FRAME, INNER[3] + FRAME)
OUTER_RADIUS = INNER_RADIUS + FRAME
FRAMES = {
    "dark": ((24, 24, 26), (225, 225, 235, 255), 60),
}
POINTS = [16, 32, 128, 256, 512]

def blank():
    return Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

def rounded_mask(box, radius):
    mask = Image.new("L", (SIZE * SCALE, SIZE * SCALE), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [value * SCALE for value in box], radius=radius * SCALE, fill=255
    )
    return mask.resize((SIZE, SIZE), Image.LANCZOS)

def fill(source, mask):
    if isinstance(source, tuple):
        source = Image.new("RGBA", (SIZE, SIZE), source)
    layer = blank()
    layer.paste(source.convert("RGBA"), (0, 0), mask)
    return layer

def ring_point(distance, box, radius):
    x0, y0, x1, y1 = box
    width, height = x1 - x0 - 2 * radius, y1 - y0 - 2 * radius
    arc = math.pi * radius / 2
    segments = [
        ("line", (x0 + radius + width / 2, y0), (x1 - radius, y0), width / 2),
        ("arc", (x1 - radius, y0 + radius), -90, 0, arc),
        ("line", (x1, y0 + radius), (x1, y1 - radius), height),
        ("arc", (x1 - radius, y1 - radius), 0, 90, arc),
        ("line", (x1 - radius, y1), (x0 + radius, y1), width),
        ("arc", (x0 + radius, y1 - radius), 90, 180, arc),
        ("line", (x0, y1 - radius), (x0, y0 + radius), height),
        ("arc", (x0 + radius, y0 + radius), 180, 270, arc),
        ("line", (x0 + radius, y0), (x0 + radius + width / 2, y0), width / 2),
    ]
    distance %= sum(segment[-1] for segment in segments)
    for segment in segments:
        if distance <= segment[-1]:
            share = distance / segment[-1]
            if segment[0] == "line":
                (ax, ay), (bx, by) = segment[1], segment[2]
                angle = math.degrees(math.atan2(by - ay, bx - ax))
                return ax + (bx - ax) * share, ay + (by - ay) * share, angle
            (cx, cy), start, end = segment[1], segment[2], segment[3]
            angle = math.radians(start + (end - start) * share)
            x, y = cx + radius * math.cos(angle), cy + radius * math.sin(angle)
            return x, y, math.degrees(angle) + 90
        distance -= segment[-1]
    raise ValueError("distance outside the frame")

def engrave(canvas, text, position, color, upright):
    font = ImageFont.truetype(FONT_PATH, FONT_SIZE * SCALE, index=1)
    inset = FRAME / 2
    box = (OUTER[0] + inset, OUTER[1] + inset, OUTER[2] - inset, OUTER[3] - inset)
    radius = (OUTER_RADIUS + INNER_RADIUS) / 2
    perimeter = (
        2 * (box[2] - box[0] - 2 * radius)
        + 2 * (box[3] - box[1] - 2 * radius)
        + 2 * math.pi * radius
    )
    widths = [font.getlength(letter) / SCALE for letter in text]
    total = sum(widths) + TRACKING * (len(text) - 1)
    direction = -1 if upright else 1
    cursor = position * perimeter - direction * total / 2
    layer = Image.new("RGBA", (SIZE * SCALE, SIZE * SCALE), (0, 0, 0, 0))
    for letter, width in zip(text, widths):
        x, y, angle = ring_point(cursor + direction * width / 2, box, radius)
        if upright:
            angle += 180
        side = int(FONT_SIZE * 2.5 * SCALE)
        glyph = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        ImageDraw.Draw(glyph).text(
            (side / 2, side / 2), letter, font=font, fill=color, anchor="mm"
        )
        glyph = glyph.rotate(-angle, resample=Image.BICUBIC)
        layer.alpha_composite(
            glyph, (int(x * SCALE - side / 2), int(y * SCALE - side / 2))
        )
        cursor += direction * (width + TRACKING)
    return Image.alpha_composite(canvas, layer.resize((SIZE, SIZE), Image.LANCZOS))

def make_magsafe_face():
    """Renders the physical MagSafe 3 connector inside the inner squircle with pure white and green glow."""
    canvas = Image.new("RGBA", (SIZE, SIZE), (28, 28, 30, 255))
    
    # 优雅深空灰金属微渐变底板
    gradient = Image.new("RGBA", (SIZE, SIZE))
    g_draw = ImageDraw.Draw(gradient)
    for y in range(SIZE):
        t = y / SIZE
        r = int(36 * (1 - t) + 18 * t)
        g = int(36 * (1 - t) + 18 * t)
        b = int(40 * (1 - t) + 22 * t)
        g_draw.line([(0, y), (SIZE, y)], fill=(r, g, b, 255))
    canvas.alpha_composite(gradient)
    
    # 主体方块尺寸：根据 0.625 比例，高 960px，宽 600px (纯直角没有任何圆角)
    body_h = 960
    body_w = 600
    cx = 1024
    cy = 1024
    
    body_x0 = cx - body_w // 2 + 50
    body_y0 = cy - body_h // 2
    body_x1 = body_x0 + body_w
    body_y1 = body_y0 + body_h
    
    draw = ImageDraw.Draw(canvas)
    
    # 1. 左侧线缆 (厚 200px)
    cable_h = 200
    cable_y0 = cy - cable_h // 2
    cable_y1 = cy + cable_h // 2
    cable_x0 = body_x0 - 320
    cable_x1 = body_x0
    draw.rectangle([cable_x0, cable_y0, cable_x1, cable_y1], fill=(240, 242, 248, 255))
    
    # 2. 中间主体方块 (纯白铝合金纯直角矩形，没有任何圆角！)
    draw.rectangle([body_x0, body_y0, body_x1, body_y1], fill=(255, 255, 255, 255))
    
    # 3. 右侧磁吸前端方块 (高 750px，宽 60px)
    tip_w = 60
    tip_h = 750
    tip_x0 = body_x1 + 18
    tip_x1 = tip_x0 + tip_w
    tip_y0 = cy - tip_h // 2
    tip_y1 = cy + tip_h // 2
    draw.rectangle([tip_x0, tip_y0, tip_x1, tip_y1], fill=(240, 242, 248, 255))
    
    # 4. 正中央指示灯 (纯翠绿与纯白同色径向光晕，绝对无任何黑圈与脏影)
    led_cx = (body_x0 + body_x1) // 2
    led_cy = cy
    
    # 在白色方块上绘制纯同色径向发光
    glow_radius = 160
    glow_img = Image.new("RGBA", (glow_radius * 2, glow_radius * 2), (0, 0, 0, 0))
    glow_arr = np.zeros((glow_radius * 2, glow_radius * 2, 4), dtype=np.uint8)
    
    for y in range(glow_radius * 2):
        for x in range(glow_radius * 2):
            d = math.hypot(x - glow_radius, y - glow_radius)
            if d <= glow_radius:
                if d < 35:
                    # 极亮白透绿聚光核心
                    t = d / 35.0
                    r = int(220 * (1 - t) + 40 * t)
                    g = 255
                    b = int(235 * (1 - t) + 115 * t)
                    glow_arr[y, x] = [r, g, b, 255]
                elif d < 75:
                    # 鲜艳纯翠绿晶圆
                    t = (d - 35) / 40.0
                    r = int(40 * (1 - t) + 140 * t)
                    g = int(245 * (1 - t) + 255 * t)
                    b = int(115 * (1 - t) + 185 * t)
                    glow_arr[y, x] = [r, g, b, 255]
                else:
                    # 纯净淡绿柔和微晕融入纯白
                    t = (d - 75) / (glow_radius - 75)
                    r = int(140 * (1 - t) + 255 * t)
                    g = 255
                    b = int(185 * (1 - t) + 255 * t)
                    glow_arr[y, x] = [r, g, b, 255]
    
    glow_img = Image.fromarray(glow_arr)
    canvas.alpha_composite(glow_img, (led_cx - glow_radius, led_cy - glow_radius))
    
    return canvas

def framed(content, style):
    frame_color, text_color, rim_alpha = FRAMES[style]
    outer = rounded_mask(OUTER, OUTER_RADIUS)
    canvas = fill((*frame_color, 255), outer)
    canvas = Image.alpha_composite(
        canvas, fill(content, rounded_mask(INNER, INNER_RADIUS))
    )
    rim = blank()
    ImageDraw.Draw(rim).rounded_rectangle(
        INNER, radius=INNER_RADIUS, outline=(255, 255, 255, rim_alpha), width=4
    )
    canvas = Image.alpha_composite(canvas, rim)
    canvas = engrave(canvas, NAME, 0.875, text_color, False)
    canvas = engrave(canvas, SIGNATURE, 0.375, text_color, True)
    shadow = fill((0, 0, 0, 85), outer).filter(ImageFilter.GaussianBlur(42))
    shadow = shadow.transform((SIZE, SIZE), Image.AFFINE, (1, 0, 0, 0, 1, -20))
    return Image.alpha_composite(shadow, canvas)

def main():
    print("▸ 正在生成纯净版 MagPulse AppIcon (无黑圈、纯白与纯绿光晕)...")
    face_img = make_magsafe_face()
    icon = framed(face_img, "dark")
    
    ICONSET.mkdir(parents=True, exist_ok=True)
    RESOURCES.mkdir(parents=True, exist_ok=True)
    
    icon.save(RESOURCES / "icon-2048.png")
    
    for point in POINTS:
        for scale in (1, 2):
            name = f"icon_{point}x{point}{'@2x' if scale == 2 else ''}.png"
            pixels = point * scale
            icon.resize((pixels, pixels), Image.LANCZOS).save(ICONSET / name)
    
    icon.resize((1024, 1024), Image.LANCZOS).save(ICONSET / "icon_512x512@2x.png")
    
    print("▸ 正在调用系统 iconutil 编译 AppIcon.icns...")
    subprocess.run(["iconutil", "-c", "icns", str(ICONSET), "-o", str(OUTPUT_ICNS)], check=True)
    print(f"✓ AppIcon.icns 重新编译成功: {OUTPUT_ICNS}")

if __name__ == "__main__":
    main()
