# AGENTS.md

给在这个仓库里干活的 AI 编码 agent（Codex、Claude Code、OpenWorkBuddy 等）。

## 这是什么

macOS 桌面锦鲤池，SwiftUI + SpriteKit，SwiftPM 工程，零依赖、零联网。源码在 `Sources/KoiPond/`，文件分工见 `skills/koipond-mod/SKILL.md`。

## 构建与验收

```bash
swift build -c release
KOI_SELFTEST=1 .build/release/KoiPond   # 必须全部 PASS
KOI_TOUR=1 .build/release/KoiPond       # 看帧率有没有掉
./build-app.sh                          # 出 dist/KoiPond.app
```

带 `KOI_*` 变量的运行不写用户设置、不影响用户正在跑的鱼塘。改了画面就用 `KOI_SNAPSHOT=/tmp/x.png` 截图自己看，别只看编译通过。

## 约定

- 主线程只做轻活，重活放后台队列。
- 持久化字段新增时必须可选，旧数据要能读。
- 不引入第三方依赖，不加任何联网代码。
- 角色素材不用真人照片或公众人物形象。
- 新增 `koipond://` 指令时同步更新 `skills/koipond-control/SKILL.md` 和 README 的指令表。

## 技能

`skills/` 下三个技能（Agent Skills 格式），仓库根的 `plugin.json` 让整个仓库能作为 Agent Plugin 安装：

- `koipond-control`：用 `koipond://` 链接遥控正在跑的鱼塘
- `koipond-fish-designer`：按描述设计锦鲤放进鱼塘
- `koipond-mod`：改源码加新玩法
