<div align="center">

# 🏮 中秋赏鱼 KoiPond

**把 Mac 桌面变成一池月下锦鲤 —— 点水撒食，鱼会游过来；画一条自己的鱼，放进去它就游**

[![GitHub stars](https://img.shields.io/github/stars/CatCatUncle/koipond?style=social)](https://github.com/CatCatUncle/koipond/stargazers)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](Package.swift)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](Package.swift)
[![Universal](https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-universal-brightgreen)](build-app.sh)

原生 SwiftUI + SpriteKit，常驻 60fps，空闲 CPU 个位数；零第三方依赖、零联网。

[下载即用](#-下载即用) · [怎么玩](#-怎么玩) · [自己编译](#️-自己编译) · [性能是怎么做的](#-性能是怎么做的) · [**企业 FDE 合作**](#-关于作者--合作)

<b>🤝 推荐搭配 <a href="https://github.com/CatCatUncle/openworkbuddy">OpenWorkBuddy</a> 使用 —— 最好用的本地开源 AI 办公 Agent</b><br>
<sub>🏢 企业 FDE 驻场 / Agent 落地 / 私有化部署合作 → <a href="mailto:contact@aijentra.com"><b>contact@aijentra.com</b></a></sub>

</div>

> [!IMPORTANT]
> ### 🤝 推荐搭配 [OpenWorkBuddy](https://github.com/CatCatUncle/openworkbuddy) 一起用
>
> **[OpenWorkBuddy](https://github.com/CatCatUncle/openworkbuddy) —— 最好用的本地开源 AI 办公 Agent。** 跑在你自己电脑上，说一句话，它自己规划、动手、验收，
> 把 PPT / Word / Excel / 网页直接落到硬盘上；DeepSeek、通义千问、豆包、Claude、Ollama 都能接。
>
> - 🏢 **适合企业本地部署**：数据不出本机 / 内网，支持 Docker 一键部署
> - 🛠️ **支持商用二次开发**：个人免费，企业商用与二次开发提供商业授权
> - 🐟 **桌面上养鱼，干活交给它**：鱼塘负责赏心悦目，报表和 PPT 让 OpenWorkBuddy 去做
>
> 👉 **[github.com/CatCatUncle/openworkbuddy](https://github.com/CatCatUncle/openworkbuddy)** [![OpenWorkBuddy stars](https://img.shields.io/github/stars/CatCatUncle/openworkbuddy?style=social)](https://github.com/CatCatUncle/openworkbuddy/stargazers)

> A native macOS desktop toy: a moonlit koi pond that lives behind your windows. Click the
> water to feed the fish, paint your own koi and release it into the pond. SwiftUI + SpriteKit,
> 60fps, zero dependencies, no network access.

> [!TIP]
> **⭐ 求一个 Star！** 如果这池鱼让你的桌面顺眼了一点，请给
> **[KoiPond](https://github.com/CatCatUncle/koipond)** 和 **[OpenWorkBuddy](https://github.com/CatCatUncle/openworkbuddy)** 都点一下 Star。

<p align="center">
  <img src="docs/img/night.jpg" alt="夜晚的鱼塘：月亮、荷叶、十几条锦鲤，顶部是控制栏" width="100%">
  <br><sub>月下鱼塘。顶部控制栏会自动收起，鼠标移到屏幕顶部中间就出来</sub>
</p>

<table>
<tr>
<td width="50%"><img src="docs/img/editor.jpg" alt="画锦鲤：在鱼身上画花纹"><br><sub>画一条锦鲤：选鱼身颜色和墨色，在鱼身上随手画，放进池塘就游起来</sub></td>
<td width="50%"><img src="docs/img/day.jpg" alt="白天的鱼塘"><br><sub>白天模式</sub></td>
</tr>
</table>

## ✨ 能做什么

| | |
|---|---|
| 🌕 **月下鱼塘** | 十几条锦鲤成群游动，荷叶浮在鱼上面，月光和萤火点点；昼夜一键切换 |
| 🍚 **撒鱼食** | 点水面撒一把，附近的鱼会游过来抢；鼠标一动鱼就散开，停一会儿又慢慢凑过来 |
| 🖌️ **画锦鲤** | 在鱼身上画自己的花纹，放进池塘后花纹贴着鱼身一起摆动；最多留 20 条，重启还在 |
| 💃 **牵手共舞 / 腹肌挑战** | 两个角色小场景，点一下有反应 |
| 🎵 **配乐** | 选一首本地音乐循环播放，不带任何内置音频 |
| 🖱️ **两种模式** | 互动模式能逗鱼；穿透模式鱼塘沉到桌面图标下面，点击全部穿过去，桌面照常用 |

## 📦 下载即用

到 [Releases](https://github.com/CatCatUncle/koipond/releases) 下载 `KoiPond-macOS.zip`，解压后把 `KoiPond.app` 拖进「应用程序」。

应用没有经过 Apple 公证，第一次打开会被拦。任选一种放行：

- 在 Finder 里**右键 → 打开**，再点一次「打开」
- 或者在终端执行：`xattr -dr com.apple.quarantine /Applications/KoiPond.app`

打开后它不占 Dock，只在菜单栏留一个图标，所有设置都在那个菜单里。

## 🎮 怎么玩

| 操作 | 效果 |
|---|---|
| 鼠标移到屏幕顶部中间 | 控制栏出来；移开几秒后自动收起。点 📌 让它常驻 |
| 点水面 | 撒鱼食 |
| 点荷叶 | 荷叶晃一下，荡开水波 |
| 控制栏「画锦鲤」 | 打开画鱼窗口，画完点「放入池塘」 |
| 菜单栏 → 穿透模式 | 鱼塘不再接收点击，桌面图标、拖文件都正常 |
| 菜单栏 → 互动模式 | 切回来逗鱼 |
| 菜单栏 → ⌘1 / ⌘2 / ⌘3 | 切场景 |
| 菜单栏 → 退出鱼塘 | ⌘Q |

## 🛠️ 自己编译

需要 macOS 14+ 和 Xcode 16（或同版本的 Command Line Tools，Swift 6）。

```bash
git clone https://github.com/CatCatUncle/koipond.git && cd koipond
./build-app.sh            # 出一个 Apple Silicon + Intel 通用、ad-hoc 签名的 dist/KoiPond.app
open dist/KoiPond.app
```

本机编译出来的不带隔离标记，直接能开。开发时也可以直接跑：

```bash
swift run -c release
```

## 🚀 性能是怎么做的

桌面挂件最怕两件事：卡住桌面，和偷偷吃 CPU。这里做了这些：

- **窗口层级**：互动模式放在桌面图标上一层、所有应用窗口下面；穿透模式沉到桌面层并忽略鼠标，永远不挡正常窗口
- **画锦鲤是独立浮动窗口**：不跟全屏鱼塘抢焦点，第一下点击就能落笔
- **角色图后台解码**：绿幕抠图和切帧在后台线程一次做完，每张图各自一把锁，切场景不等别的图
- **鱼的纹理缓存**：同款花色只画一次，画的花纹按弧长均匀取点，不随笔速变密
- **定时器跑在 common mode**：拖菜单、拖窗口时动画也不停
- **主线程卡顿看门狗**：主线程超过 250ms 没响应会记到 `~/Library/Logs/KoiPond/stalls.log`，方便排查
- **单实例**：新打开的会替换旧的，不会叠出两个鱼塘

## 🧪 调试开关

都是环境变量，给开发和自动化测试用，带这些变量启动时不写用户设置、不替换正在跑的实例：

| 变量 | 作用 |
|---|---|
| `KOI_SELFTEST=1` | 跑 10 项自检（窗口层级、点击分发、控制栏、画鱼窗口），打印 PASS/FAIL 后退出 |
| `KOI_TOUR=1` | 依次切过每个场景和开关，打印每一步的帧率和最慢一帧 |
| `KOI_SNAPSHOT=out.png` | 启动后截一张鱼塘图就退出（配 `KOI_SNAPSHOT_DELAY` 秒数） |
| `KOI_SCENE=pond\|dance\|touch` | 指定开场场景 |
| `KOI_NIGHT=0\|1`、`KOI_EDITOR=1`、`KOI_TOOLBAR=0\|1` | 昼夜、打开画鱼窗口、控制栏显隐 |
| `KOI_STATS=1`、`KOI_FPS=30` | 显示 SpriteKit 统计、限制帧率 |

```bash
swift build -c release && KOI_SELFTEST=1 .build/release/KoiPond
```

## 🗂️ 代码结构

```
Sources/KoiPond/
├── KoiPondApp.swift      # 应用入口、窗口、菜单栏、自检和巡检
├── PondStage.swift       # 鱼塘：群游、撒食、水波、荷叶
├── FishArt.swift         # 锦鲤绘制和纹理缓存
├── PortraitStages.swift  # 角色小场景
├── Sprites.swift         # 角色图加载、绿幕抠图、切帧
├── Overlay.swift         # 控制栏、提示、画锦鲤编辑器
├── PondState.swift       # 状态与持久化
├── StageScene.swift      # 场景基类
├── Models.swift          # 场景、颜色、锦鲤数据
└── Diagnostics.swift     # 帧率统计、卡顿看门狗
```

## ⭐ Star History

如果这个项目对你有用，**请给 [KoiPond](https://github.com/CatCatUncle/koipond) 和 [OpenWorkBuddy](https://github.com/CatCatUncle/openworkbuddy) 一起点个 Star**，这是对开源作者最好的支持。

[![Star History Chart](https://api.star-history.com/svg?repos=CatCatUncle/koipond,CatCatUncle/openworkbuddy&type=Date)](https://star-history.com/#CatCatUncle/koipond&CatCatUncle/openworkbuddy&Date)

## 👋 关于作者 · 合作

开发者猫叔，前大厂 Agent 工程师，有丰富的 Agent 落地实践经验。

- ✔️ 服务过跨境电商、制造业、AI 初创、私募金融机构、消费品巨头、国央企等客户的 AI 解决方案
- ✔️ 企业 AI 内训 ｜ 企业私有化部署 ｜ 行业智能体 ｜ AI 数字化全案 ｜ AI 搜索优化 ｜ Agent 项目落地

常驻深圳，欢迎前来交流和考察。

> [!IMPORTANT]
> ## 🚀 找开发者猫叔做企业 FDE（驻场工程）与 AI 落地
>
> - **FDE 驻场工程**：工程师进驻企业，把 Agent 从 Demo 做到真正上线、真正有人用
> - **企业私有化部署**：OpenWorkBuddy 等 Agent 在企业内网落地，数据不出域
> - **行业智能体 / Agent 项目定制开发**、**企业 AI 内训**、**AI 数字化全案**、**AI 搜索优化（GEO）**
>
> ### 📮 直接发邮件：**[contact@aijentra.com](mailto:contact@aijentra.com)**

## 📄 License

[MIT](LICENSE)。角色图为 AI 生成素材，随代码一起以 MIT 发布。
