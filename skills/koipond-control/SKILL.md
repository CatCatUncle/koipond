---
name: koipond-control
description: 遥控用户 Mac 桌面上的「中秋赏鱼」鱼塘（KoiPond）：切场景、昼夜、撒鱼食、在鱼塘上弹一条提示、截图看效果。用户提到鱼塘/锦鲤/桌面鱼，或想要一种不打扰的桌面提醒（番茄钟、构建跑完、定时喝水）时使用。
---

# 遥控桌面鱼塘

KoiPond 注册了 `koipond://` 链接。用 `open -g` 打开链接就能指挥正在跑的鱼塘；没在跑会自动启动（`-g` 不抢前台焦点）。

## 先确认装好了

```bash
open -Ra KoiPond || echo "没装"
```

没装就告诉用户去 https://github.com/CatCatUncle/koipond/releases 下载，别替用户下载安装未签名应用。

## 指令表

| 想做什么 | 链接 |
|---|---|
| 切场景 | `koipond://scene/pond` · `koipond://scene/dance` · `koipond://scene/touch` |
| 夜晚 / 白天 / 切换 | `koipond://night?on=1` · `koipond://night?on=0` · `koipond://night` |
| 撒鱼食（会自动回鱼塘） | `koipond://feed?x=0.5&y=0.4`（x、y 是 0–1，y 从上往下） |
| 弹提示 | `koipond://caption?title=标题&text=正文&seconds=6`（标题 ≤40 字，正文 ≤120 字，1–30 秒） |
| 互动 / 穿透模式 | `koipond://mode?interactive=1` · `koipond://mode?interactive=0` |
| 放走所有画的锦鲤 | `koipond://fish/release` |
| 截图 | `koipond://snapshot?path=/绝对路径/out.png` |
| 放一条锦鲤 | 见 `koipond-fish-designer` 技能 |

中文和特殊字符必须 URL 编码。最省事的是用同仓库的脚本（它会编码、会检查应用是否装好）：

```bash
python3 <koipond 目录>/skills/koipond-fish-designer/scripts/koi-link.py caption "该起来走走了" "已经坐了 50 分钟"
python3 <koipond 目录>/skills/koipond-fish-designer/scripts/koi-link.py feed 0.5 0.5
```

## 看效果

改完状态想确认，用截图指令，等一两秒再读图：

```bash
open -g "koipond://snapshot?path=/tmp/koipond.png" && sleep 1.5
```

截图只有鱼塘本身，不含桌面和其他窗口。

## 常用玩法

- **番茄钟**：到点发 `caption` + 在屏幕中间 `feed` 一把，鱼群聚过来就是提醒，不弹系统通知、不打断手上的事。
- **长任务跑完**：`npm test && open -g "koipond://caption?title=测试通过" || open -g "koipond://night?on=1"`——成功弹提示，失败池塘入夜。
- **定时**：用户要「每天几点提醒」时，用 cron/launchd 或所在 agent 平台的定时任务调用上面的链接，先把要写进 crontab 的那一行给用户确认。

## 规矩

- 弹提示是给用户看的，写人话、写要做的动作；别连发，同一件事一次就够。
- 不要把鱼塘切到穿透模式后又不告诉用户——穿透模式下鱼塘点不动。
- 链接指令不需要任何权限，不读写用户文件（截图只写到你给的路径）。
