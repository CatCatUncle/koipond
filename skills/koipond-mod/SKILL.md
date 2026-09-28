---
name: koipond-mod
description: 改「中秋赏鱼」KoiPond 的 Swift 源码加新玩法——新的内置锦鲤品种、新配色、新的点击反应、节日主题、新的链接指令——改完编译、跑自检、截图验收。用户想让鱼塘「多一个功能/换个主题/加个场景」而不只是放一条鱼时使用。
---

# 给鱼塘加新玩法

仓库：https://github.com/CatCatUncle/koipond 。SwiftPM 工程，macOS 14+，Swift 6 工具链，零第三方依赖。

## 先看地图

| 文件 | 管什么 |
|---|---|
| `Models.swift` | 场景枚举 `PondScene`、颜色 `Palette`、锦鲤数据 `KoiSpec` / `KoiPattern` |
| `FishArt.swift` | 锦鲤怎么画（身体、鳍、花斑、笔画），按花色缓存纹理 |
| `PondStage.swift` | 鱼塘：群游、撒食、水波、荷叶、点击反应 |
| `PortraitStages.swift` | 角色小场景（精灵图 + 点击动作） |
| `Commands.swift` | `koipond://` 链接的解析 |
| `KoiPondApp.swift` | 窗口、菜单栏、链接执行、自检 `runSelfTest`、巡检 `runTour` |
| `Overlay.swift` | 控制栏和画锦鲤编辑器（SwiftUI） |

## 改的时候守住这几条

- **主线程不做重活**。解码图片、生成纹理放后台；主线程卡顿超过 250ms 会被看门狗记进 `~/Library/Logs/KoiPond/stalls.log`。
- **加新品种**：`KoiPattern` 末尾追加 case（别插中间，已存的鱼按序号解码），在 `FishArt.swift` 里画花斑。
- **加新场景**：`PondScene` 加 case 和 `key`，`KoiPondApp.makeStage` 和 `hint(for:)` 各补一行，控制栏和菜单会自动出现。角色图放 `Resources/`，绿幕底，横排 4 帧，在 `SpriteSheet` 里登记。**不要用真人照片或公众人物形象。**
- **加链接指令**：`PondCommand` 加 case 和解析，`AppDelegate.handle(link:)` 里执行，自检里补一条解析断言，`skills/koipond-control/SKILL.md` 的指令表同步。
- 新的 `UserDefaults` 字段一律可选、带默认值，老用户升级不能丢已画的鱼。

## 验收（每次改完都跑）

```bash
swift build -c release
KOI_SELFTEST=1 .build/release/KoiPond          # 全部 PASS 才算过
KOI_TOUR=1 .build/release/KoiPond              # 每一步 60fps 左右、最慢一帧别超过 120ms
KOI_SCENE=pond KOI_NIGHT=1 KOI_SNAPSHOT=/tmp/koi.png .build/release/KoiPond   # 截图自己看一眼
KOI_LINKS="koipond://feed?x=0.5&y=0.5 koipond://caption?title=hi" KOI_SNAPSHOT=/tmp/koi.png .build/release/KoiPond
```

带 `KOI_*` 调试变量启动时用的是一次性设置、不会顶掉用户正在跑的鱼塘，放心跑。

打包给用户：`./build-app.sh`，产物在 `dist/KoiPond.app`（通用二进制、ad-hoc 签名）。
