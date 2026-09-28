---
name: koipond-fish-designer
description: 按用户的描述设计一条锦鲤（鱼身颜色、花斑颜色、在鱼身上画的图案或笔画），直接放进 Mac 桌面的「中秋赏鱼」鱼塘里游。用户说「画一条……的锦鲤」「给鱼塘加条鱼」「做一条中秋/生日/团队主题的鱼」时使用。
---

# 设计一条锦鲤放进鱼塘

一条鱼 = 鱼身颜色 + 花斑颜色 + 花纹。花纹两种来源：内置品种，或者你画的笔画。放进去之后重启还在，最多留 20 条，超出时最老的一条游走。

## 最快：用脚本

`scripts/koi-link.py` 只用 Python 标准库：

```bash
S=<本技能目录>/scripts/koi-link.py
python3 $S fish --body "#F5E8C7" --mark "#D4452A" --preset heart          # 白底红心
python3 $S fish --body "#1F2A33" --mark "#F0C060" --preset moon --scale 1.4  # 黑底金月牙，个头大一点
python3 $S fish --body "#F4F1EA" --mark "#D4452A" --preset crown          # 丹顶：头顶一块红
python3 $S fish --pattern ogon --body "#E9B44C" --mark "#C9652A"           # 内置黄金品种，不画笔画
```

- `--preset` 可叠加：`--preset wave --preset dots`。可选 heart / moon / star / wave / stripes / dots / crown。
- `--ink` 单独指定预设图案的颜色（默认同 `--mark`）。
- `--pattern` 内置品种：kohaku（红白）/ tancho（丹顶）/ showa（昭和三色）/ ogon（黄金）/ custom（只有你画的笔画）。
- `--scale` 0.6–1.6，`--speed` 0.4–1.6。
- `--print` 只输出链接不打开，适合先给用户看。

## 自己画笔画

写一个 JSON 数组，每一笔是一条折线：

```json
[
  {"points": [[0.30, 0.25], [0.30, 0.75]], "color": "#D4452A", "width": 0.12},
  {"points": [[0.30, 0.50], [0.55, 0.50]], "color": "#D4452A", "width": 0.12},
  {"points": [[0.55, 0.25], [0.55, 0.75]], "color": "#D4452A", "width": 0.12}
]
```

```bash
python3 $S fish --body "#F5E8C7" --mark "#D4452A" --strokes h.json
```

坐标系（最容易错的地方）：

- 坐标是**鱼身包围盒**里的比例，0–1。**x=1 是鱼头**，x=0 是鱼尾那一端；**y 从上往下**。
- 鱼身是纺锤形，四个角落在身体外面会被裁掉。图案放在 x 0.2–0.8、y 0.2–0.8 之间最稳。
- 鱼头朝右时字是正的；鱼一游起来会转向，所以字母、简单汉字（十、王、中）能认，笔画多的字会糊，别硬画。
- `width` 是相对鱼身高度的笔粗，0.02–0.3，常用 0.06–0.12。每条最多 64 笔、每笔 400 个点。
- 曲线就多给点：一个圆 16–40 个点就够顺滑。

## 做完要验

放完等两三秒（新鱼会从池塘中间游出来），截一张图看一眼再告诉用户：

```bash
open -g "koipond://snapshot?path=/tmp/koi-check.png" && sleep 1.5
```

看不清就放大 `--scale` 或加粗 `width`，别凭感觉说「画好了」。

## 配色参考

| 名字 | 鱼身 | 花斑 |
|---|---|---|
| 红白 | #F5E8C7 | #D4452A |
| 墨鲤 | #1F2A33 | #F0C060 |
| 黄金 | #E9B44C | #C9652A |
| 青鲤 | #3B6663 | #F5E8C7 |
| 樱花 | #F7E3E6 | #E07A93 |

不想要了：`python3 $S release` 放走所有画的鱼（内置那一群不受影响）。
