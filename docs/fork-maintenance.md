# Fork 维护与上游同步

这份文档记录 `dnw3/tinycast` 的源码维护约定：保留 Capture / Translation，持续吸收
`abue-ammar/tinycast` 的 feature 和 fix。功能细节沿用各自文档，后续同步时更新这里的基线与验证记录。

## 仓库与分支

以下是 2026-10-12 核对的配置。remote 名称属于本地 checkout；换机器或新 clone 后先运行
`git remote -v` 和 `git branch -vv`，按实际 URL 确认，不能只凭 `origin` 这个名字判断角色。

| 角色 | 仓库 / ref | 用途 |
| --- | --- | --- |
| 原仓库 | [abue-ammar/tinycast](https://github.com/abue-ammar/tinycast)，本地 `upstream` | 从 `upstream/main` 获取上游源码 |
| 我们的 fork | [dnw3/tinycast](https://github.com/dnw3/tinycast)，本地 `origin` | 推送维护结果 |
| 当前维护分支 | [`dnw/capture-workspace`](https://github.com/dnw3/tinycast/tree/dnw/capture-workspace) | Capture / Translation 的集成分支，跟踪 `dnw3/dnw/capture-workspace` |
| fork 的 `main` | `origin/main` | 尚未包含本轮集成；当前功能入口是上面的维护分支 |

下文命令按这套 remote 名称书写；其他 checkout 的名称不同时，按 URL 替换。
GitHub 的 Sync fork 操作或更新 fork 的 `main`，不能代替维护分支上的冲突处理与验证。

## 翻译分支统一维护

`dnw/capture-workspace` 是 Capture 与 Translation 的统一维护入口。
`dnw/translation-panel` 保留为早期实现的历史参考，不再单独维护同一套翻译功能。

2026-10-10 对比 `17580527` 与集成分支 `e37f3d9f`：独立翻译窗口、自动语言方向、
Apple / AI 引擎、选中文字回填及原有翻译测试均已整合；集成分支进一步增加截图 OCR 接入、
截图预览、选段翻译和多段批量翻译。旧分支的 `b6ce5314` 仅隔离已被新版上游删除的
`codex-turn-test` / `installed-ai-test`，无需恢复这项测试启动配置。

这次整合以集成分支的现有源码为准，使用保留当前树的 merge 记录旧翻译分支已被吸收，
避免重新引入旧上游实现。两个远程分支均保留，fork `main` 不变。
这条 merge 记录也是维护分支改用 merge 同步上游的原因，见下文。

无需合入 `main` 就能从维护分支构建安装。本地 Release 安装使用同一个自签名身份，
替换前保留旧应用备份。当前 Release 更新源仍指向上游，不能用应用内更新保留 fork 功能；
后续更新此安装需继续从维护分支重新构建。

本次本机验证：101 个 harness 全部通过（174 秒），Debug / Release 构建通过，
无 Swift 编译警告，仅有 AppIntents 元数据提取提示；lint 检查通过并保留既有警告，
Model import 纯度及严格签名检查通过。未重新执行截图、翻译质量或录制的原生验收，
此前交付状态中的未关闭项仍然有效。

## 我们保留的改动

| 范围 | 内容与维护入口 |
| --- | --- |
| Capture | 截图、长截图、编辑、贴图、OCR、录制、导出与历史；源码在 `Tinycast/Features/Capture/`，约束见 [Capture](features/capture.md) |
| Translation | 独立翻译窗口、Apple / AI 引擎、划词及截图文本、受校验的回填；源码在 `Tinycast/Features/Translation/`，约束见 [Translation](features/translation.md) |
| 共享接入 | `AppCore` 所有权、命令与热键、设置、剪贴板、`Platform/TextRecognition/` 和 `TextInjector`；同步时适配上游的新 API，保留双方行为 |
| WebP | 用户批准的官方 libwebp 依赖及短生命周期 helper；版本、校验和、更新规则见 [Vendor/README.md](../Vendor/README.md) |

Capture 仍有原生验收未关闭。以[交付状态](plans/capture-delivery-status.md)和
[验收清单](plans/capture-acceptance.md)为准；源码、构建、单元回归通过，分别记录，不扩写成完整交付结论。

## 后续如何跟进上游

上游入口：[main 提交](https://github.com/abue-ammar/tinycast/commits/main/)、
[Pull requests](https://github.com/abue-ammar/tinycast/pulls)、
[Releases](https://github.com/abue-ammar/tinycast/releases)。合入 `main` 的修复可能尚未发布到 Release。

可以直接把下面这些请求交给 Codex；仓库内的 [AGENTS.md](../AGENTS.md) 和本文件提供上下文。

| 请求示例 | 执行范围 |
| --- | --- |
| “看看上游最近有哪些值得同步的改动，先给我摘要。” | 拉取并比较当前基线、上游提交及相关 PR，说明影响，保留维护分支内容 |
| “同步上游最新 main，保留 Capture/Translation，测试后推送。” | merge 上游、处理冲突与本地化、验证并推送到 fork 的维护分支 |
| “把上游这个 PR/commit 的 fix 同步过来。”附链接 | 核对改动及依赖，选择必要提交，验证后推送 |

优先关注与我们接入点重叠的变更：AppCore 生命周期、命令/热键、AI provider、设置及备份、
剪贴板/OCR、TextInjector、窗口焦点、权限、helper 打包、签名和更新源。上游新增功能也应保留其自身约束。

## 同步全部更新

维护分支用 merge 吸收 `upstream/main`，不再 rebase。分支里有记录旧翻译分支已被吸收的 merge；
线性 rebase 会把旧分支提交重新放回维护分支，而本地化等大范围提交每次 rebase 都要重解同样的冲突。
merge 只解决新增冲突，也不改写已发布的历史。

命令均从仓库根目录运行。先检查未提交改动并提交或单独备份，再切到维护分支；不要把未确认的工作混入合并。

```sh
git status --short --branch
git remote -v
git fetch upstream --prune
git fetch origin --prune
git switch dnw/capture-workspace
git log --oneline HEAD..upstream/main
git merge-base --is-ancestor origin/dnw/capture-workspace HEAD
git branch "dnw/backup-capture-$(date +%Y%m%d-%H%M%S)" HEAD
git merge --no-ff --no-commit upstream/main
```

祖先检查返回 0 才继续；否则先整合 fork 远端的新提交。遇到冲突，按职责合并：保留上游演进，
给本地功能适配新接口；逐项检查命令、设置与备份、权限描述、AppCore 初始化/关闭、OCR 和打包，
不能整文件选一边覆盖另一边。上游删除了我们只做过本地化的文件时，接受删除，再把文案本地化
移到上游的替代实现里。`project.pbxproj` 冲突取上游版本后运行 `xcodegen generate`；
其他生成文件也通过各自生成器更新。`Vendor/libwebp/` 保持官方源码，按其 README 更新。
需要放弃本次合并时用 `git merge --abort`。

上游新增的界面文案需要单独补本地化：`String` 参数（`FormRow`、`SettingsRow(title:)`、
`primaryActionTitle`、`.tooltip`、`PopoverMenuItem` 等）在调用处改为 `String(localized:)`，
Model 层不本地化。用 `SWIFT_EMIT_LOC_STRINGS=YES` 构建后运行
`./Scripts/sync-localization.sh build/UpstreamCheck`，补齐它报告缺少的中文，删除 `stale` 条目。
运行时才拼出键的显示名（如 `HyperKeyPhysicalKey.title`、命令标题、设置搜索条目）不会被提取，
需在目录里以 `manual` 条目补齐。

## 只同步一个 feature 或 fix

先确认 PR 的状态、实际改动和依赖；已合并 PR 使用上游实际落地的 commit。
检查当前分支是否已经包含等价修复，再按依赖顺序 `git cherry-pick -x <commit-sha>`，让提交保留来源。
merge commit 需先检查父提交与差异，不能直接猜 `-m` 的值。未合并 PR 的代码需明确记录其未合并状态。

同样先备份、解决冲突、验证并推送。以后合并上游时复核这些提交是否已被上游覆盖，避免重复补丁。

## 验证与推送

同步源码后按 [testing.md](testing.md#definition-of-done) 完成全量 harness、lint、Model import
纯度检查和 Debug 构建，保证没有新增警告。涉及 Capture helper、导出、工程或打包时补 Release 构建。
开发过程中先跑受影响的 harness；收尾再跑全量。警告需区分上游既有项与本轮新增项。

构建检查使用独立 DerivedData，例如 `build/UpstreamCheck`，避免覆盖正在运行的 Dev bundle：

```sh
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug \
  -derivedDataPath build/UpstreamCheck CODE_SIGNING_ALLOWED=NO SWIFT_EMIT_LOC_STRINGS=YES build
```

该命令只验证编译。影响截图输出、翻译回填、焦点、权限或资源释放的改动，再验证对应的原生路径；
历史证据保留原日期和源码范围，未执行或未关闭的验收项继续标明。将验证结果及本次上游 SHA 写回文档后提交。

merge 同步与普通提交都是快进推送：

```sh
git push origin HEAD:refs/heads/dnw/capture-workspace
```

推送被拒绝说明远端有新提交，先 fetch 并整合，不能改用强推覆盖。推送后用
`git ls-remote origin refs/heads/dnw/capture-workspace` 与 `git rev-parse HEAD` 核对，再检查工作区状态。

日常源码同步的推送目标是 fork 的维护分支。合入 fork `main`、提交上游 PR 和发布应用分别按对应任务执行；
向上游贡献时遵循 [CONTRIBUTING.md](../CONTRIBUTING.md) 的 issue / `approved` 约定。

## 源码同步与应用更新

当前 README 的 Homebrew、Release 链接以及代码里的 `ReleaseFeed.repository` 都指向原仓库。
这些安装入口提供上游构建，尚无独立的 fork 发布链路。

本地使用维护分支时，按 [development.md](development.md) 配置签名后运行
`./Scripts/build-and-run.sh`，构建并启动该 checkout 的 `Tinycast Dev.app`（`com.tinycast.app.dev`）。
Dev 不通过应用内更新器更新，继续使用本分支的新代码需要重新构建。

如果以后正式分发 fork，再统一处理应用名称、bundle ID、签名、更新源、发布资源和安装说明；
源码同步或推送成功不代表这条发布链路已经完成。现有机制见 [updates](features/updates.md) 与 [release](release.md)。

## 最近一次源码同步

| 项目 | 2026-10-12 记录 |
| --- | --- |
| 上游基线 | `888b5e59fc39f62c7c42ad6ab42f689e6b233eeb`（上一轮 `da2c4e44`） |
| 同步方式 | merge `upstream/main` 到维护分支，合并前备份为 `dnw/backup-capture-20261012-185805` |
| 吸收的上游改动 | 启动器表单（Snippets / Quicklinks / 自定义命令 / 日程）、Hyper Key 扩展与诊断、⌘C 选区兜底及借用互斥、AI 拒绝原因、AI Chat 快捷键、扩展依赖、Notes 列表、应用扫描符号链接、UTF-8 解码 |
| 主要适配 | `TextInjector.copySelection` 同时保留上游借用互斥/暂停记录与翻译的菜单 Copy、取消校验；AI 状态提示改由 Service 本地化后交给 `AIProviderFailure`；上游删除的编辑面板改为本地化新表单；补 81 条中文、删 18 条失效键 |
| 自动检查 | 119 个 harness、Debug / Release 通过；Swift 警告 0；lint 153 项与合并前相同，新增 0（上游自身 66 项） |
| 原生验收 | 本轮未执行；启动器新表单、Hyper Key 设置与诊断、翻译取词的中文界面和行为尚未在安装版复验 |
| 证据 | 合并提交说明；此前的[机器可读检查](plans/capture-evidence/rebase-checks-20261010.json)、[Capture 交付状态](plans/capture-delivery-status.md)保留 |

下次同步时更新本节的日期、上游 SHA、改动摘要、验证范围与证据链接；旧证据文件保留，便于回溯。
