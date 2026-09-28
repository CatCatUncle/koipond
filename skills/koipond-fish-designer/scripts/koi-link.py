#!/usr/bin/env python3
"""Build and open koipond:// links. Only the Python standard library.

  koi-link.py scene dance            # pond / dance / touch
  koi-link.py night on|off|toggle
  koi-link.py feed 0.5 0.4           # x, y in 0..1, y pointing down
  koi-link.py caption "标题" "正文" [秒数]
  koi-link.py fish --body "#F5E8C7" --mark "#D4452A" --preset heart [--strokes a.json] [--scale 1.3]
  koi-link.py release                # 放走所有画的锦鲤
  koi-link.py snapshot /abs/path.png # 让正在跑的鱼塘截一张图
  koi-link.py mode interactive|passthrough

Add --print to only print the link instead of opening it.
"""
import argparse
import json
import math
import subprocess
import sys
import urllib.parse

SCHEME = "koipond://"


def q(value):
    return urllib.parse.quote(str(value), safe="")


# ---- stroke presets: points are 0..1 of the fish body, x=1 is the head, y points down ----

def _circle(cx, cy, r, n=40, start=0.0, end=2 * math.pi):
    return [[round(cx + r * math.cos(start + (end - start) * i / n), 3),
             round(cy + r * math.sin(start + (end - start) * i / n), 3)] for i in range(n + 1)]


def preset(name, color):
    if name == "heart":
        pts = []
        for i in range(61):
            t = 2 * math.pi * i / 60
            x = 16 * math.sin(t) ** 3
            y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
            pts.append([round(0.52 + x / 60, 3), round(0.46 - y / 55, 3)])
        return [{"points": pts, "color": color, "width": 0.07}]
    if name == "moon":
        # A thick arc round the tail side reads as a crescent moon opening toward the head.
        return [{"points": _circle(0.52, 0.5, 0.24, n=48, start=math.radians(60), end=math.radians(300)), "color": color, "width": 0.13}]
    if name == "star":
        pts = []
        for i in range(11):
            r = 0.3 if i % 2 == 0 else 0.12
            a = -math.pi / 2 + i * math.pi / 5
            pts.append([round(0.52 + r * math.cos(a), 3), round(0.5 + r * math.sin(a), 3)])
        return [{"points": pts, "color": color, "width": 0.06}]
    if name == "wave":
        return [{"points": [[round(0.08 + 0.84 * i / 40, 3), round(y0 + 0.07 * math.sin(i / 40 * 4 * math.pi), 3)]
                            for i in range(41)], "color": color, "width": 0.07} for y0 in (0.35, 0.62)]
    if name == "stripes":
        return [{"points": [[x, 0.12], [x - 0.05, 0.88]], "color": color, "width": 0.09} for x in (0.3, 0.48, 0.66)]
    if name == "dots":
        spots = [(0.3, 0.35), (0.5, 0.6), (0.68, 0.35), (0.4, 0.75)]
        return [{"points": _circle(x, y, 0.07, n=16), "color": color, "width": 0.1} for x, y in spots]
    if name == "crown":  # a red cap on the head, like a tancho
        return [{"points": _circle(0.78, 0.5, 0.1, n=24), "color": color, "width": 0.18}]
    raise SystemExit(f"没有这个图案：{name}。可选 heart / moon / star / wave / stripes / dots / crown")


def build(args):
    c = args.cmd
    if c == "scene":
        return f"{SCHEME}scene/{q(args.name)}"
    if c == "night":
        return f"{SCHEME}night" + ("" if args.state == "toggle" else f"?on={1 if args.state == 'on' else 0}")
    if c == "feed":
        return f"{SCHEME}feed?x={args.x}&y={args.y}"
    if c == "caption":
        return f"{SCHEME}caption?title={q(args.title)}&text={q(args.text)}&seconds={args.seconds}"
    if c == "release":
        return f"{SCHEME}fish/release"
    if c == "snapshot":
        return f"{SCHEME}snapshot?path={q(args.path)}"
    if c == "mode":
        return f"{SCHEME}mode?interactive={1 if args.mode == 'interactive' else 0}"
    if c == "fish":
        strokes = []
        for name in args.preset or []:
            strokes += preset(name, args.ink or args.mark)
        if args.strokes:
            with open(args.strokes, encoding="utf-8") if args.strokes != "-" else sys.stdin as f:
                strokes += json.load(f)
        parts = [f"body={q(args.body)}", f"mark={q(args.mark)}", f"scale={args.scale}", f"speed={args.speed}"]
        if args.pattern:
            parts.append(f"pattern={args.pattern}")
        if strokes:
            parts.append("strokes=" + q(json.dumps(strokes, separators=(",", ":"))))
        return f"{SCHEME}fish?" + "&".join(parts)
    raise SystemExit(__doc__)


def main():
    p = argparse.ArgumentParser(description="打开 koipond:// 链接遥控桌面鱼塘", usage=__doc__)
    p.add_argument("--print", action="store_true", help="只打印链接，不打开")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("scene").add_argument("name", choices=["pond", "dance", "touch"])
    sub.add_parser("night").add_argument("state", choices=["on", "off", "toggle"])
    f = sub.add_parser("feed"); f.add_argument("x", type=float); f.add_argument("y", type=float)
    c = sub.add_parser("caption"); c.add_argument("title"); c.add_argument("text", nargs="?", default=""); c.add_argument("seconds", nargs="?", type=float, default=5)
    sub.add_parser("release")
    sub.add_parser("snapshot").add_argument("path")
    sub.add_parser("mode").add_argument("mode", choices=["interactive", "passthrough"])
    fish = sub.add_parser("fish")
    fish.add_argument("--body", default="#F5E8C7", help="鱼身颜色 #RRGGBB")
    fish.add_argument("--mark", default="#D4452A", help="花斑颜色 #RRGGBB")
    fish.add_argument("--ink", help="预设图案的颜色，默认同 --mark")
    fish.add_argument("--pattern", choices=["kohaku", "tancho", "showa", "ogon", "custom"])
    fish.add_argument("--preset", action="append", help="heart / moon / star / wave / stripes / dots / crown，可叠加多个")
    fish.add_argument("--strokes", help="笔画 JSON 文件，- 表示从标准输入读")
    fish.add_argument("--scale", type=float, default=1.2)
    fish.add_argument("--speed", type=float, default=0.95)
    args = p.parse_args()

    link = build(args)
    if args.print:
        print(link)
        return
    r = subprocess.run(["open", "-g", link], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("打不开 koipond:// 链接：先装好并打开一次 KoiPond.app（https://github.com/CatCatUncle/koipond/releases）\n" + r.stderr.strip())
    print(link if len(link) < 200 else link[:200] + "…")


if __name__ == "__main__":
    main()
