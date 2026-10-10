# 原生翻译一期实施 Plan

对应 [Spec](translation-spec.md)。范围包含真实引擎接入；模拟数据只用于开发验证。

## 实施顺序

- [x] 对照 Tinycast / Easydict 源码，确认语言判断、入口和回填缺口。
- [x] 定义原生窗口交互、模块边界和一期验收。
- [x] 实现纯语言策略、请求状态和输出契约，建立固定样本 harness。
- [x] 实现原生输入窗口、语言菜单、结果和键盘操作。
- [x] 补齐默认 Mini、内容自适应、展开收起、置顶和未置顶时失焦关闭；投递期间保护焦点切换。
- [x] 接入 Apple 与现有 AI provider，打通取消与过期响应隔离。
- [x] 将 Translate 从 Quick Actions 独立，连接命令、快捷键与设置。
- [x] 增加原目标捕获与回填前核对，保留 TextInjector 既有投递路径。
- [x] 完成聚焦测试、Debug build、lint、全部 harness 和纯度检查。
- [x] 原生交互验证，记录真实服务与跨应用验证边界，更新正式功能文档。
- [x] 默认 Mini 放在当前屏幕右上角，实测窗口坐标、失焦/置顶、展开收起和 AI 中英翻译。
- [x] 输入停顿 800 ms 后自动翻译，移除底部按钮行；结果旁提供复制图标和回填菜单，选择器显示下拉箭头。
- [ ] 下载 Apple 语言包、授予 Dev 辅助功能权限后，验收 Apple 实译与跨应用回填。

## 约束

- 使用既有 Theme、InterfaceMetrics 与 NSPanel 模式；不修改 EdgeDissolve 或 ThinScrollbar。
- 不引入 Easydict 的第三方依赖、旧系统兼容层、新的 singleton 或 actor。
- 不改变其他 Quick Actions、AI Chat、snippets 的操作语义。
- 当前工程已有用户改动；生成 Xcode project 时保留这些改动。
- 不创建分支、提交、PR 或发布；交付本地可审阅改动。

## 验证记录

验证日期：2026-09-22。本机为 macOS 27 / Xcode 27；工程部署目标继续为 macOS 26+。

| 检查 | 结果 |
| --- | --- |
| `./Scripts/run-tests.sh` | 77 个 harness 全部通过 |
| `./Scripts/run-tests.sh translation-test` | 128 项断言通过，包含 50 条语言识别样本、防抖取消、原生 TextKit composition、窗口生命周期和定位策略 |
| `./Scripts/build-and-run.sh --build-only` | Debug 构建通过；无新增代码编译警告 |
| `./Scripts/lint.sh` | 通过；新增 Translation 代码无 lint 告警，仓库其他文件保留既有告警 |
| Model 层 AppKit / SwiftUI / Cocoa 导入检查 | 无命中 |
| `git diff --check` | 通过 |

原生窗口实测覆盖：启动器 Translate 入口、空白输入自动聚焦、连续英文输入、中文粘贴、
语言自动识别与中英方向、全选、Shift-Return 换行、Return 提交、Escape 关闭、独立设置，
以及语言包缺失和 AI 未配置时保留原文并给出恢复入口。辅助功能未授权时仍能手输。
修复了初始焦点以及非激活浮窗的原生编辑快捷键转发。验证用快捷键已清除，恢复原先未绑定状态。

首次全量检查有 3 个失败。`codex-turn-test` 与 `installed-ai-test` 在原始 HEAD 也失败：
登录 shell 改写 PATH，让测试调用了真实 Codex / OpenCode。测试 worker 现在隔离 zsh 启动
目录，保留 fixture PATH；不更改用户的 shell 或实际 provider 行为。图标渲染测试单独重跑
通过，随后完整的 77 个 harness 全部通过。

Mini 补充验证时，首轮全量中 `ext-test` 的子进程回调在固定 1.5 秒等待后仍为 `pending`，
单独重跑 294 项断言全部通过，随后完整重跑 77 个 harness 全部通过；没有修改扩展实现或放宽测试断言。

### 解锁后的 Mini 实测

- Mini 原生截图为 420 pt 宽，空白原文自动聚焦；展开为 640 × 540 pt，收起保留输入、语言与结果。
- 系统日志记录屏幕可用区 `(0, 91, 1728, 993)`，初始窗口 `(1300, 816, 420, 260)`，
  展开 `(1080, 536, 640, 540)`，收起后的错误状态 `(1300, 730, 420, 346)`。
  三种状态的右边缘均为 1720、顶部均为 1076，距离可用区域右侧和顶部各 8 pt。
- 语言、引擎菜单均可操作；菜单中的 Escape 只收起菜单，不关闭翻译窗口。
- 打开 Tinycast 设置使未置顶窗口失焦：日志为 `pinned=false delivering=false dismiss=true`，
  随即记录 `Dismiss translation window`。置顶后同样切换，日志为 `dismiss=false`，返回后原文保留。
- 置顶时打开系统 Language & Region，确认跨应用失焦事件为 `pinned=true ... dismiss=false`，
  返回后 `Pinned query` 原文和缺语言包提示仍在。
- 新开未置顶 Mini 后打开同一系统设置，日志出现 `pinned=false ... dismiss=true` 并立即关闭，
  确认跨应用的关闭路径，而不把自动化工具仅抬起窗口当作焦点转移证据。
- 当前 Dev 已有 AI 模型 GPT-5.5 / Low。英译中、包含数字 42 和 URL 的中译英、六段中文长文
  均返回真实译文。长文保持段落、数字、日期和 URL，Mini 结果区滚动条可到达 1，末段可见。
- 修改原文使旧结果及 Copy 立即失效；翻译进行中展开窗口没有取消请求，结果继续返回。
- Apple 缺少语言包时显示恢复入口，且能打开系统语言设置；本轮未下载语言包或修改系统权限。

日志类别为 `TranslationWindow`，只记录窗口坐标、失焦策略和关闭事件，不记录原文、译文或模型凭据。
多屏坐标及拖动后定位由纯几何测试覆盖；本轮没有实测外接屏拖动。

### 自动翻译与精简操作区

- 对照本地 Easydict 源码：输入自动翻译延迟 0.8 秒，手输自动翻译默认关闭，选区自动翻译默认开启。
  Tinycast 按本次需求默认启用手输和粘贴后的自动翻译，不增加新的设置开关。
- 实测不按 Return 输入英文，AI 返回中文；点击复制图标变为对勾，粘贴回原文的内容与译文一致，
  随后自动识别为中文并返回英文。新编辑会清除旧结果和复制状态。
- Mini 不再有底部 Translate / Copy / Replace 按钮行；复制移到结果右上角，回填与重试放入 `⋯`。
  Command-Shift-C、Command-Return 和 Return 保留。回填仍要求有效的原目标。
- 最终原生截图确认引擎和语言选择器的右侧下拉箭头可见；Apple 与 AI 位于同一层菜单，实测切换后恢复 AI。
- 最终版本再次无回车输入英文，返回正确中文；`⋯` 显示 Translate Again 和禁用的 Replace selection，
  与当前无可验证目标一致。菜单 Escape、展开和收起均保留原文与译文，最终恢复 Mini。
- 新增可控等待的防抖测试，覆盖连续输入合并、手动提交去重、清空/关闭取消、候选期间暂停和提交后重启。
  真实 TextKit 2 对象验证 `setMarkedText`、`insertText`、`unmarkText` 的状态回调；共 128 项断言通过。
- 全量首轮再次命中 `ext-test` 既有的固定等待超时；该项单独重跑通过，随后以
  `TINYCAST_TEST_JOBS=4 ./Scripts/run-tests.sh` 完整验证 77 个 harness 全部通过，不修改扩展代码或断言。
- Debug 构建通过；Translation 无新增编译或 lint 告警，Model 纯度及 `git diff --check` 通过。

### 尚未实测的边界

- 本机未安装当前中英语言对的 Apple 翻译语言包；Apple 实译仍待验证。
  AI 已实测三条样本，不代表广泛语种或复杂专业内容的质量评测；取消与截断边界仍由 fixture 验证。
- Dev 未获辅助功能授权，跨应用取词、替换、插入及目标变化时的真实投递尚未运行。
  原目标匹配由纯策略测试验证，投递前的焦点与可编辑性检查已接入真实 TextInjector。
- 中文输入法候选提交和实体键盘的全局快捷键仍需人工实测。已验证快捷键录制与清除；
  UI 自动化发送的应用内键盘事件不能作为 Carbon 全局热键已触发的证据。
- AX 无法确认选区时进入手输；不模拟 Command+C，避免编辑器的“无选区复制整行”行为。

### 运行

Codex Run 按钮或 `./Scripts/build-and-run.sh` 启动本地 `Tinycast Dev.app`。启动器搜索
`Translate`，或在 Settings → Translation 配置自己的快捷键。Apple 在系统 Language & Region
下载语言；AI 在 Settings → AI 配置 provider 后，到 Translation 选择独立模型。

当前未提交、未发布。生成的 Xcode 工程保留本次开始前已有的本机签名与产物引用改动。
