# Fork 维护与上游同步

这份文档记录 `dnw3/tinycast` 的源码维护约定：保留 Capture / Translation，持续吸收
`abue-ammar/tinycast` 的 feature 和 fix。功能细节沿用各自文档，后续同步时更新这里的基线与验证记录。

## 仓库与分支

以下是 2026-10-10 核对的配置。remote 名称属于本地 checkout；换机器或新 clone 后先运行
`git remote -v` 和 `git branch -vv`，按实际 URL 确认，不能只凭 `origin` 这个名字判断角色。

| 角色 | 仓库 / ref | 用途 |
| --- | --- | --- |
| 原仓库 | [abue-ammar/tinycast](https://github.com/abue-ammar/tinycast)，本地 `origin` | 从 `origin/main` 获取上游源码 |
| 我们的 fork | [dnw3/tinycast](https://github.com/dnw3/tinycast)，本地 `dnw3` | 推送维护结果 |
| 当前维护分支 | [`dnw/capture-workspace`](https://github.com/dnw3/tinycast/tree/dnw/capture-workspace) | Capture / Translation 的集成分支，跟踪 `dnw3/dnw/capture-workspace` |
| fork 的 `main` | `dnw3/main` | 尚未包含本轮集成；当前功能入口是上面的维护分支 |

本 checkout 没有名为 `upstream` 的 remote。其他教程中的 `upstream/main` 在这里对应 `origin/main`。
GitHub 的 Sync fork 操作或更新 fork 的 `main`，不能代替维护分支上的冲突处理与验证。

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
| “同步上游最新 main，保留 Capture/Translation，测试后推送。” | 完整 rebase、处理冲突、验证并推送到 fork 的维护分支 |
| “把上游这个 PR/commit 的 fix 同步过来。”附链接 | 核对改动及依赖，选择必要提交，验证后推送 |

优先关注与我们接入点重叠的变更：AppCore 生命周期、命令/热键、AI provider、设置及备份、
剪贴板/OCR、TextInjector、窗口焦点、权限、helper 打包、签名和更新源。上游新增功能也应保留其自身约束。

## 同步全部更新

命令均从仓库根目录运行。先检查未提交改动并提交或单独备份，再切到维护分支；不要把未确认的工作混入 rebase。

```sh
git status --short --branch
git remote -v
git fetch origin --prune
git fetch dnw3 --prune
git switch dnw/capture-workspace
git log --oneline HEAD..origin/main
git log --oneline origin/main..HEAD
```

确认本地已包含 fork 远端现有提交；若双方各有提交，先检查并整合差异。记录远端原值和本地备份，
既用于复核，也用于最后的推送保护。下列变量在同一个 shell 会话中保留到推送结束。

```sh
capture_remote_before=$(git rev-parse dnw3/dnw/capture-workspace)
git merge-base --is-ancestor "$capture_remote_before" HEAD
```

只有祖先检查返回 0 才继续：

```sh
capture_before=$(git rev-parse HEAD)
capture_base_before=$(git merge-base HEAD origin/main)
git branch "dnw/backup-capture-$(date +%Y%m%d-%H%M%S)" "$capture_before"
git rebase origin/main
```

遇到冲突，按职责合并：保留上游演进，给本地功能适配新接口；
逐项检查命令、设置与备份、权限描述、AppCore 初始化/关闭、OCR 和打包，不能整文件选一边覆盖另一边。
`project.yml` 冲突解决后运行 `xcodegen generate`，提交生成的 project；其他生成文件也通过各自生成器更新。
`Vendor/libwebp/` 保持官方源码，按其 README 更新。

冲突处理后用 `git add` 和 `git rebase --continue`；需要取消本次尚未结束的 rebase 时用 `git rebase --abort`。
完成后复核本地补丁的变化，确认没有漏掉功能：

```sh
git range-diff "$capture_base_before..$capture_before" "origin/main..HEAD"
git diff --check
```

## 只同步一个 feature 或 fix

先确认 PR 的状态、实际改动和依赖；已合并 PR 使用上游实际落地的 commit。
检查当前分支是否已经包含等价修复，再按依赖顺序 `git cherry-pick -x <commit-sha>`，让提交保留来源。
merge commit 需先检查父提交与差异，不能直接猜 `-m` 的值。未合并 PR 的代码需明确记录其未合并状态。

同样先备份、解决冲突、验证并推送。以后完整 rebase 时复核这些提交是否已被上游覆盖，避免重复补丁。

## 验证与推送

同步源码后按 [testing.md](testing.md#definition-of-done) 完成全量 harness、lint、Model import
纯度检查和 Debug 构建，保证没有新增警告。涉及 Capture helper、导出、工程或打包时补 Release 构建。
开发过程中先跑受影响的 harness；收尾再跑全量。警告需区分上游既有项与本轮新增项。

构建检查使用独立 DerivedData，例如 `build/UpstreamCheck`，避免覆盖正在运行的 Dev bundle：

```sh
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug \
  -derivedDataPath build/UpstreamCheck CODE_SIGNING_ALLOWED=NO build
```

该命令只验证编译。影响截图输出、翻译回填、焦点、权限或资源释放的改动，再验证对应的原生路径；
历史证据保留原日期和源码范围，未执行或未关闭的验收项继续标明。将验证结果及本次上游 SHA 写回文档后提交。

普通新增提交使用：

```sh
git push dnw3 HEAD:refs/heads/dnw/capture-workspace
```

已发布的维护分支经过 rebase 后需要改写历史，使用开始前记录的远端 SHA：

```sh
git push --force-with-lease=refs/heads/dnw/capture-workspace:"$capture_remote_before" \
  dnw3 HEAD:refs/heads/dnw/capture-workspace
```

lease 被拒绝说明远端有变化，先读取和整合差异，不能只替换期望 SHA 后重试。推送后用
`git ls-remote dnw3 refs/heads/dnw/capture-workspace` 与 `git rev-parse HEAD` 核对，再检查工作区状态。

日常源码同步的推送目标是 fork 的维护分支。合入 fork `main`、提交上游 PR 和发布应用分别按对应任务执行；
向上游贡献时遵循 [CONTRIBUTING.md](../CONTRIBUTING.md) 的 issue / `approved` 约定。

## 源码同步与应用更新

当前 README 的 Homebrew、Release 链接以及代码里的 `ReleaseFeed.repository` 都指向原仓库。
这些安装入口提供上游构建，尚无独立的 fork 发布链路。

本地使用维护分支时，按 [development.md](development.md) 配置签名后运行
`./Scripts/build-and-run.sh`，构建并启动该 checkout 的 `Tinycast Dev.app`（`com.tinycast.app.dev`）。
Dev 不通过应用内更新器更新，继续使用本分支的新代码需要重新构建。

如果以后正式分发 fork，再统一处理应用名称、bundle ID、签名、更新源、发布资源和安装说明；
源码 rebase 或推送成功不代表这条发布链路已经完成。现有机制见 [updates](features/updates.md) 与 [release](release.md)。

## 最近一次源码同步

| 项目 | 2026-10-10 记录 |
| --- | --- |
| 上游基线 | `da2c4e44238b166f774bd3d63e37d12b0616af94` |
| 初次整理快照 | [`38c29fda`](https://github.com/dnw3/tinycast/commit/38c29fdadcc6353df36d094c345e803406b5406b)，三个提交分别为官方 libwebp、Capture/Translation、设计与验收证据 |
| 主要适配 | 上游 AI Chat / Dictation / settings-file / Clipboard、命令别名、玻璃背景 API；修复 Drive 授权取消竞态 |
| 自动检查 | 101 个 harness、Debug / Release 通过；Swift 警告 0；lint 与上游同为 66 项，新增 0 |
| 原生验收 | 本轮未重新执行；2026-09-29 历史证据及未关闭项保留 |
| 证据 | [机器可读检查](plans/capture-evidence/rebase-checks-20261010.json)、[Capture 交付状态](plans/capture-delivery-status.md) |

下次同步时更新本节的日期、上游 SHA、改动摘要、验证范围与证据链接；旧证据文件保留，便于回溯。
