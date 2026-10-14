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
| 集成分支 | fork 的 `main`（默认分支） | 上游加 Capture / Translation；构建安装从这里出，只用 merge 吸收上游 |
| 上游镜像 | fork 的 `upstream-main` | 上游 `main` 的纯拷贝，由同步 workflow 快进，不放我们的提交 |
| 功能分支 | `dnw/<功能名>` | 从 `main` 切出，做完合回 `main` |

下文命令按这套 remote 名称书写；其他 checkout 的名称不同时，按 URL 替换。
2026-10-12 起集成分支由 `dnw/capture-workspace` 改为 `main`；之前的记录和证据里出现的
`dnw/capture-workspace` 指同一条历史。不要点 GitHub 页面的 Sync fork：它作用于默认分支，
`main` 与上游分叉后它提供的 Discard commits 会丢掉我们的提交。

## 翻译分支统一维护

集成分支是 Capture 与 Translation 的统一维护入口。
`dnw/translation-panel` 保留为早期实现的历史参考，不再单独维护同一套翻译功能。

2026-10-10 对比 `17580527` 与集成分支 `e37f3d9f`：独立翻译窗口、自动语言方向、
Apple / AI 引擎、选中文字回填及原有翻译测试均已整合；集成分支进一步增加截图 OCR 接入、
截图预览、选段翻译和多段批量翻译。旧分支的 `b6ce5314` 仅隔离已被新版上游删除的
`codex-turn-test` / `installed-ai-test`，无需恢复这项测试启动配置。

这次整合以集成分支的现有源码为准，使用保留当前树的 merge 记录旧翻译分支已被吸收，
避免重新引入旧上游实现。两个远程分支均保留，fork `main` 不变。
这条 merge 记录也是集成分支改用 merge 同步上游的原因，见下文。

本地 Release 安装从 `main` 构建，使用同一个自签名身份，替换前保留旧应用备份。
应用内更新指向 fork 自己的 Releases，见"给熟人分发"。

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

可以直接把下面这些请求交给 Codex 或 Claude Code；仓库内的 [AGENTS.md](../AGENTS.md) 和本文件提供上下文。

| 请求示例 | 执行范围 |
| --- | --- |
| “看看上游最近有哪些值得同步的改动，先给我摘要。” | 拉取并比较当前基线、上游提交及相关 PR，说明影响，保留 `main` 内容 |
| “同步上游最新 main，保留 Capture/Translation，测试后推送。” | merge 上游、处理冲突与本地化、验证并推送到 fork 的 `main` |
| “处理一下同步 PR。” | 读同步 PR 和 CI 结果，解决冲突或补本地化后推送 `main` |
| “把上游这个 PR/commit 的 fix 同步过来。”附链接 | 核对改动及依赖，选择必要提交，验证后推送 |

优先关注与我们接入点重叠的变更：AppCore 生命周期、命令/热键、AI provider、设置及备份、
剪贴板/OCR、TextInjector、窗口焦点、权限、helper 打包、签名和更新源。上游新增功能也应保留其自身约束。

## 自动同步

两个 fork 专用 workflow 负责发现上游更新和跑检查，合并仍由人决定：

| Workflow | 触发 | 做什么 |
| --- | --- | --- |
| [`upstream-sync.yml`](../.github/workflows/upstream-sync.yml) | 每天北京时间约 09:17，或 Actions 页手动 | 把上游 `main` 快进到 `upstream-main`；`main` 落后时开或更新 PR `upstream-main → main`，正文列出上游提交和预演出的冲突文件 |
| [`ci.yml`](../.github/workflows/ci.yml) | 指向 `main` 的 PR、`main` 的推送、手动 | `macos-26` 上检查生成的工程、Model 纯度、lint 与本地化、Debug / Release 构建、全量 harness |

同步 PR 的三种结果：

- **无冲突、CI 绿**：用 **Create a merge commit** 合并。不能 squash 或 rebase，也不能删除 `upstream-main`
  （仓库设置的 *Automatically delete head branches* 保持关闭）。
- **无冲突、CI 红**：多数是上游新增文案缺中文，或上游改动碰到我们的接入点。在本地 `main` 上补齐后推送，CI 重跑。
- **有冲突**：按下一节在本地 merge `origin/upstream-main` 并推送 `main`。PR 的提交进入 `main` 后会自动标为已合并。

CI 只覆盖自动检查。合并后按需从 `main` 重新构建安装，原生验收仍手动进行。

CI runner 使用它上面最新的 Xcode（2026-10 为 Xcode 26.6 / Swift 6.3），比本机的 Xcode 27 旧，
也与上游 release 构建一致；本机能编过、CI 编不过时，按旧编译器的限制改写代码，不要在 CI 里换版本绕过。
`ci.yml` 的 `HOST_DEPENDENT` 列出结果取决于主机的 harness：`capture-ocr-test` 逐字比对小字 OCR，
Vision 识别器随 macOS 版本变化；`form-input-test` 检查离屏渲染的字形像素，runner 上画不出来；
`capture-video-test` 依赖视频编码，runner 虚拟机的虚拟化编码器偶尔挂住直到 300 秒超时。
它们在 CI 失败只记警告并写进运行摘要，合并前须在本机跑通；其他 harness 失败一律判红。

上游的 `release.yml`、`triage.yml`、`coauthors.yml`、`website.yml` 在 fork 里已停用
（`gh workflow disable`，不改文件，避免与上游冲突）。上游以后新增 workflow 时，同步后在 Actions 页确认并停用。

`upstream-sync.yml` 需要仓库 secret `UPSTREAM_SYNC_TOKEN`：默认 `GITHUB_TOKEN` 推不了上游对
`.github/workflows/` 的修改，它开的 PR 也不会触发 CI。在 GitHub → Settings → Developer settings →
Fine-grained tokens 创建令牌，仓库只选 `dnw3/tinycast`，权限 Contents、Pull requests、Workflows 设为
Read and write，然后存入仓库 Settings → Secrets and variables → Actions。令牌过期后同步任务会失败，届时更换。
公开仓库 60 天没有提交时 GitHub 会停用定时任务，需在 Actions 页重新启用。

同步 PR 用仓库所有者的令牌创建，GitHub 不会为此通知所有者本人，所以提醒走飞书自定义机器人
（[`Scripts/notify-lark.sh`](../Scripts/notify-lark.sh)）：新开同步 PR 或上游有新提交、同步 PR 的 CI
跑完、同步 workflow 失败时各发一条；上游没动不重复发。在飞书群的群机器人里添加自定义机器人并开启签名校验，
把 webhook 地址和密钥存为仓库 secret `LARK_WEBHOOK_URL`、`LARK_WEBHOOK_SECRET`。未配置时跳过通知，
飞书拒收只记警告，都不影响同步与 CI。配置或更换后，在 Actions 页手动运行 Upstream sync 并勾选
*Also send a test message* 验证。

## 处理同步 PR

收到飞书"新的同步 PR"或"同步 PR 的 CI 结果"后，或被要求"处理一下同步 PR"时，按顺序：

1. 读 PR：`gh pr list -R dnw3/tinycast --head upstream-main`，再 `gh pr view <号> -R dnw3/tinycast`。
   正文列出上游提交和预演出的冲突文件。
2. 看 CI：`gh pr checks <号> -R dnw3/tinycast`；排队较久时等它结束，不在 CI 未完成时合并。
3. 按情况处理：
   - **无冲突、CI 绿**：运行摘要里有 `capture-ocr-test` / `form-input-test` 的警告时，先在本机
     `./Scripts/run-tests.sh <名字>` 跑通；再 `gh pr merge <号> -R dnw3/tinycast --merge`。
     只能用 `--merge`，不加 `--delete-branch`。
   - **无冲突、CI 红**：读失败步骤的日志（`gh run view <run> -R dnw3/tinycast --log-failed`）。
     本地化缺中文、旧编译器不兼容等在本地 `main` 上合并 `origin/upstream-main` 后修复，按"同步全部更新"验证并推送。
   - **有冲突**：按下一节"同步全部更新"在本地 merge、解决并推送 `main`；PR 会自动标为已合并。
4. 上游改动涉及接入点（AppCore、命令/热键、设置、剪贴板、TextInjector、权限等）时，把影响告诉用户；
   合并后需要用新版本时按"本机安装"重新构建安装；要让熟人也拿到，经用户同意后按"给熟人分发"发版。
5. 更新文末"最近一次源码同步"：日期、上游 SHA、改动摘要、验证结果。只合并了无关改动（如 CI 配置）可略过。

## 同步全部更新

同步 PR 有冲突、或需要手动同步时使用。`main` 用 merge 吸收上游，不再 rebase。分支里有记录旧翻译分支
已被吸收的 merge；线性 rebase 会把旧分支提交重新放回，而本地化等大范围提交每次 rebase 都要重解同样的冲突。
merge 只解决新增冲突，也不改写已发布的历史。

命令均从仓库根目录运行。先检查未提交改动并提交或单独备份，再切到 `main`；不要把未确认的工作混入合并。
合并对象用 `origin/upstream-main`，与同步 PR 一致；它落后于上游时先在 Actions 页手动跑一次同步。

```sh
git status --short --branch
git remote -v
git fetch origin --prune
git switch main
git merge --ff-only origin/main
git log --oneline HEAD..origin/upstream-main
git branch "dnw/backup-main-$(date +%Y%m%d-%H%M%S)" HEAD
git merge --no-ff --no-commit origin/upstream-main
```

`--ff-only` 失败说明本地 `main` 有未推送的提交，先整理清楚再合并。遇到冲突，按职责合并：保留上游演进，
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
git push origin main
```

推送被拒绝说明远端有新提交，先 fetch 并整合，不能改用强推覆盖。推送后用
`git ls-remote origin refs/heads/main` 与 `git rev-parse HEAD` 核对，再检查工作区状态，并确认 CI 结果。
确认无误后删除本地备份分支。

日常源码同步的推送目标是 fork 的 `main`。合入 fork `main`、提交上游 PR 和发布应用分别按对应任务执行；
向上游贡献时遵循 [CONTRIBUTING.md](../CONTRIBUTING.md) 的 issue / `approved` 约定。

## 本机安装

本机使用的是 `/Applications/Tinycast.app`（`com.tinycast.app`），由 `main` 构建的签名 Release，
与 Dev 版并存。签名身份必须是钥匙串里的 `Tinycast Self-Signed`，否则辅助功能、屏幕录制等授权会失效。

```sh
git switch main && git pull --ff-only
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Release \
  -derivedDataPath build/InstallRelease build
APP=build/InstallRelease/Build/Products/Release/Tinycast.app
codesign --verify --deep --strict "$APP"
# 两条输出的 designated requirement 必须一致，否则停下检查签名证书。
codesign -d -r- "$APP"; codesign -d -r- /Applications/Tinycast.app
ditto /Applications/Tinycast.app "build/install-backups/Tinycast-before-$(date +%Y%m%d-%H%M%S).app"
osascript -e 'tell application id "com.tinycast.app" to quit'; sleep 2
rm -rf /Applications/Tinycast.app && ditto "$APP" /Applications/Tinycast.app
codesign --verify --deep --strict /Applications/Tinycast.app && open /Applications/Tinycast.app
```

`build/` 不进 git。确认新版正常后删除 `build/install-backups/` 里的旧应用备份，它们每份约 20 MB。

## 新机器或新会话

**新会话**：`AGENTS.md` 指向本文件，直接说"处理一下同步 PR""同步上游""重新安装"即可；
不依赖任何会话记忆。GitHub 上的 workflow、secret（`UPSTREAM_SYNC_TOKEN`、`LARK_WEBHOOK_URL`、
`LARK_WEBHOOK_SECRET`）和飞书机器人都在线上，重装系统不受影响。

**新机器或重装系统**：

1. 工具：Xcode、`brew install xcodegen swiftlint`、Node、`gh`（`gh auth login`）。
2. 代码与 remote：
   ```sh
   git clone git@github.com:dnw3/tinycast.git && cd tinycast
   git remote add upstream https://github.com/abue-ammar/tinycast.git
   git config remote.upstream.tagOpt --no-tags
   git fetch upstream
   ```
3. 签名证书：从备份导入 `Tinycast Self-Signed`（SHA-1 `CCC45372…D170`，有效期至 2036-10）：
   ```sh
   security import Tinycast-Self-Signed.p12 -k ~/Library/Keychains/login.keychain-db \
     -P '<备份密码>' -T /usr/bin/codesign
   security find-identity -p codesigning | grep "Tinycast Self-Signed"
   ```
   **不要重新生成**：新证书的签名与已安装应用不同，所有系统授权都要重新给，熟人也收不到应用内更新。
   2026-10-12 已导出 `.p12` 并演练过导入，由用户保管在密码管理器。重新备份时在"钥匙串访问 → 我的证书"里
   右键这一项单独导出；不要用 signing.md 的 `security export -t identities`，它会导出钥匙串里的全部身份，
   包括公司设备证书。
4. 验证：`./Scripts/run-tests.sh`、`./Scripts/lint.sh`，然后按"本机安装"构建安装。

## 给熟人分发

面向少数熟人，不申请 Apple Developer ID、不做公证。机制只有三点：

- **更新源是 fork**：`ReleaseFeed.repository` 为 `dnw3/tinycast`，应用只看本仓库的 Releases。
  指回上游会让熟人的副本被"更新"成不含 Capture / Translation 的上游版，CI 的
  *Updates come from the fork* 步骤会拦下这种改动；同步上游时若此处冲突，保留 `dnw3/tinycast`。
- **签名是信任根**：更新器接受与运行中副本叶证书相同的包，所以每个版本都必须由本机钥匙串里的
  `Tinycast Self-Signed` 签名。证书丢失后，所有熟人都要手动重装新签名的版本并重新授权，
  按"新机器或新会话"备份 `.p12`。
- **通道是 `com.tinycast.app` 正式版**：版本号独立编号、只用 `X.Y.Z`，从 1.0.0 起，每次发版递增；
  一般每合并一轮上游加次版本号，仅修复加修订号。不能和上游安装并存，安装说明会提示先卸载上游版。

发版在本机运行，证书不离开本机：

```sh
git switch main && git pull --ff-only
./Scripts/release-fork.sh 1.2.0             # 构建、校验、打包，生成 build/dist/ 下的 zip 和说明
./Scripts/release-fork.sh 1.2.0 --publish   # 检查无误后发布 GitHub Release v1.2.0
```

脚本要求 `main` 干净且与 `origin/main` 一致，版本号大于上一个 Release；构建只含 arm64，并核对版本、
bundle ID、各可执行文件架构和签名叶证书。说明以 `<!-- tinycast:install -->` 分隔：上半部分是更新内容，
显示在应用的更新窗口；下半部分是首次安装步骤（卸载上游版、解压拖入、系统设置里"仍要打开"）和源码链接，
满足 AGPL 提供源码的要求。发布是公开操作，执行 `--publish` 前须经用户确认。

熟人首次安装需要手动放行一次；之后应用自己下载的更新不带隔离标记，不会再被 Gatekeeper 拦下，
签名不变，已授权限保留。发布后可按"本机安装"或直接用应用内更新升级本机。

`upstream` remote 设置了 `tagOpt = --no-tags`（`git config remote.upstream.tagOpt --no-tags`），
避免上游将来的 `vX.Y.Z` 标签与 fork 的发布标签在本地冲突。

## 源码同步与应用更新

README 的 Homebrew 与下载链接仍是上游的官方构建，不含 fork 功能；fork 的构建只经 fork Releases 分发。

本地使用 `main` 时，按 [development.md](development.md) 配置签名后运行
`./Scripts/build-and-run.sh`，构建并启动该 checkout 的 `Tinycast Dev.app`（`com.tinycast.app.dev`）。
Dev 不通过应用内更新器更新，继续使用本分支的新代码需要重新构建。

面向更多人的正式分发还需要 Developer ID 签名与公证、独立的应用名和 bundle ID，目前不做；现有机制见 [updates](features/updates.md) 与 [release](release.md)。

## 最近一次源码同步

| 项目 | 2026-10-14 记录 |
| --- | --- |
| 上游基线 | `1c3c2572`（上一轮 `9a9739bf`，经 PR #1） |
| 同步方式 | 同步 PR #2 有冲突，按"同步全部更新"在本地 merge `origin/upstream-main` 后推送 `main` |
| 吸收的上游改动 | 文件搜索改为自建磁盘索引（新 `FileIndexHelper`，需完全磁盘访问权限）、扩展 OAuth 登录、听写键触发快捷键、已启用的 MCP 工具可执行命令和读文件、计算器 `/单位` 与油耗单位、`fs.stat` 时间、Bring! 表单、About 版本号可复制 |
| 主要适配 | 9 处冲突均为本地化包装与上游文案/接口叠加：`InfoRow(keycaps:)`、Onboarding 改 `Text`、文件搜索文案；`file-search.md` 与 `project.pbxproj` 取上游；新增文件搜索界面文案改为 `String(localized:)`；补 34 条中文与 6 条 `manual` 键（设置锚点、搜索条目、油耗类别），删 9 条失效键 |
| 自动检查 | 120 个 harness 中 119 个通过；`form-input-test` 在合并前的 `main` 上同样失败（本机离屏渲染），与本次无关；Debug / Release 通过，Swift 警告 0；lint 165 项，新增 12 项均为上游代码 |
| 原生验收 | 本轮未执行；文件搜索的完全磁盘访问授权、索引构建与中文界面，扩展 OAuth、听写键尚未在安装版复验 |
| 证据 | 合并提交说明 |
| 后续 | 安装版需重新构建；发版时确认 `Contents/Helpers/FileIndexHelper` 已签名 |

下次同步时更新本节的日期、上游 SHA、改动摘要、验证范围与证据链接；旧证据文件保留，便于回溯。
