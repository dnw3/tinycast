# Agent 模式实施计划（Claude Code、Codex）

状态：v0.1，2026-10-19。交互见[交互设计](agent-interaction.md)，原型见 [agent-prototype](agent-prototype/index.html)。
本轮只做 Claude Code 和 Codex；pi 和通用 ACP 之后再接。

## 1. 切分

| 切片 | 内容 | 状态 |
| --- | --- | --- |
| 1 | 每个对话的工作文件夹和模式；Claude、Codex 跑 agent 回合；授权走 Tinycast；会话续接；工具行按类型显示 | 已实现，待真机验证 |
| 2 | 改动汇总与撤销；计划条；运行中排队和插话 | 未开始 |
| 3 | 后台提醒（HUD、菜单栏圆点）；侧边栏收起后悬停滑出 | 已实现，待真机验证 |
| 4 | 项目（多文件夹、读写/只读）；附件交路径；复用 CLI 自己的 skills、MCP 等开关 | 未开始 |

每个切片单独可用、单独提交，过完 [Definition of Done](../testing.md#definition-of-done) 再进下一个。

## 2. 实测过的事实（本机，2026-10-19）

### Claude Code 2.1.303

- 只发 `initialize` 控制请求、不调用模型的情况下，以下参数都被接受：
  - `--permission-mode` 取 `default` 和 `manual` 都可以；帮助文本列出的可选值为 `acceptEdits`、`auto`、`bypassPermissions`、`manual`、`dontAsk`、`plan`；
  - `--permission-prompt-tool stdio`；
  - `--tools "Read,Glob,Grep,Edit,Write,Bash,TodoWrite"`；
  - `--settings '{"disableAllHooks":true}'`。
- 会话：首轮用 `--session-id <uuid>`，之后用 `--resume <uuid>`；`--no-session-persistence` 表示不落盘。
- 不能用 `--restricted`。它会跳过用户的 settings 文件，而本机的认证正好放在 `~/.claude/settings.json` 的 `env` 里（网关地址和 token）。Tinycast 不读这些凭据，只能让 CLI 照常加载它们。
- 本机 settings 里配了 hooks 和插件。agent 回合要用 `--settings` 传 `disableAllHooks`，否则用户自己的 hook 可能先于 Tinycast 回答授权。

### Codex 0.162.1 app-server（`codex app-server generate-ts` 生成的类型）

- `item/commandExecution/requestApproval` 带 `itemId`、`command`、`cwd`、`commandActions`、`reason`。回复 `{decision}`，取值为 `accept`、`acceptForSession`、`decline`、`cancel` 等。
- `item/fileChange/requestApproval` 只带 `itemId`、`reason`、`grantRoot`。diff 在先到的 `item/started`：`fileChange.changes[] = {path, kind: add | delete | update(move_path), diff}`。
- `SandboxPolicy` 有两种：`readOnly {networkAccess}`；`workspaceWrite {writableRoots, networkAccess, excludeTmpdirEnvVar, excludeSlashTmp}`。
- `AskForApproval` 取值为 `untrusted`、`on-request`、`never`、`granular`。
- 这些参数可以在不同层级设置：
  - `thread/start` 和 `thread/resume`：`cwd`、`approvalPolicy`、`sandbox`；
  - `turn/start`：`cwd`、`approvalPolicy`、`sandboxPolicy`，对本轮及之后生效。
- 条目类型：`commandExecution`、`fileChange`、`mcpToolCall`、`plan`、`reasoning`、`agentMessage`、`webSearch`、`imageView`、`contextCompaction`。

## 3. 模式映射

| 模式 | Claude Code | Codex |
| --- | --- | --- |
| 只读 | `--tools Read,Glob,Grep` | `readOnly` 沙箱，禁网；`approvalPolicy: never` |
| 询问 | 加上 `Edit,Write,Bash,TodoWrite`；`--permission-mode default`；授权交给宿主 | `workspaceWrite`（可写目录只有这个文件夹），禁网；`approvalPolicy: untrusted` |
| 自动编辑 | 同“询问”，但用 `--permission-mode acceptEdits` | 同“询问”，文件夹内的文件改动由 Tinycast 自动接受 |

- **Codex 不用 `on-request`**：它会让沙箱里的命令不问就跑，和“命令仍会询问”不符。
- **Codex 不回 `acceptForSession`**：“本次对话都允许”由 Tinycast 自己记住，每次照常回 `accept`。这样授权始终由 Tinycast 决定，两条路由的行为也一致。
- **Claude 不发 `updatedPermissions`**：理由同上。
- **删除每次都问**：“自动编辑”不自动接受删除，“本次对话都允许”也不覆盖删除；删除卡片没有这个按钮，↵ 不生效。

## 4. 切片 1 落地情况

已实现。lint 和 Debug 构建通过；`run-tests.sh` 124 个里只有 `form-input-test`、`cleanup-walk-test` 失败，它们编译的源文件这次都没改，在本机原本就失败。CLI 行为用脚本实测过（见下文），界面还没有实际操作过。

| 层 | 文件 |
| --- | --- |
| 模型（只依赖 Foundation） | `AgentMode`、`AgentWorkspace`、`AgentApprovalRequest`、`AgentApprovalDecision`、`AgentGrants`、`AgentApprovalPolicy`、`AgentSession`、`AgentThread`、`ClaudeAgentTool`、`ClaudeAgentLaunch`、`CodexApproval`、`CodexAgentTurn` |
| 协议与解码 | `ClaudeControlProtocol.agentRequest` / `response(to:decision:)`；`InstalledAIStreamDecoder` 的 `agent` 参数 |
| 运行 | `InstalledCLIProvider`（Claude agent 回合）；`CodexTurnRunner` + `ChatGPTSubscriptionManager.agentClient`（Codex 单独的 app-server） |
| 状态与持久化 | `AIChatState` 的授权队列和本会话授权；`ChatHistoryStore` 的 `conversation_agents`、`message_tool_kinds` |
| 界面 | 输入框行的文件夹、模式菜单；`AgentApprovalCard`；工具行按类型显示图标和文案 |
| 测试 | `agent-test`（新）；`ai-chat-test` 增加持久化和授权队列 |

和交互稿不一致的地方（有意为之，后续切片再改）：

- 按钮沿用 MCP 已有的文案：“不允许 · 允许此对话 · 允许”，不新造“拒绝 / 本次对话都允许”。
- 回复进行中，文件夹和模式菜单不可用；交互稿里的“询问 → 自动编辑”（下一轮生效）留到切片 2。
- 卡片的出现动效和回复里的选项一致（从下方移入并淡入），没有单独做 10pt 上移加缩放。
- ⎋ / ⌥↵ 只在输入框有焦点时生效；焦点在转录里时，⎋ 仍然关闭窗口，卡片保留，重新打开窗口还在。
- 授权结果不单独留一行，而是落在那一步自己的行上：等待时显示“等待运行 …”和举手图标，拒绝后显示“未运行 …”（不算失败），允许后照常显示“已运行 …”。
- 读取文件夹外的内容时，卡片标题统一写“读取文件夹外的内容”，路径放在正文里。

用本机 CLI 实测过（2026-10-19，脚本驱动，不经过界面）：

- Claude 2.1.303：
  - 首轮的 `--session-id` 就是 `system/init` 里的会话 id；
  - 文件夹内的读取不会来问，`Edit`、`Bash` 会通过 `can_use_tool` 来问，而且 `tool_use` 先于提问到达；
  - 普通拒绝后本轮会继续，模型会说明情况；
  - redirect（带 `interrupt`）后，本轮以 `error_during_execution` 结束（没有 `result`，退出码 1），之后 `--resume` 能正常接上。Tinycast 把这种结束当作正常结束，不报错；
  - 恢复一个不存在的会话时，结果帧没有 `result`，原因（`No conversation found`）写在 `errors` 里，stderr 也有一份。解码器读 `errors`，`lost()` 不依赖 stderr 和退出的先后顺序；
  - 删除走的是 `Bash rm`，作为命令来问。
- Codex 0.162.1：
  - `untrusted` 下所有命令都会来问，连 `cat`、`ls` 也不例外。请求里的 `commandActions` 是 Codex 自己对命令的解读（read、search、listFiles、unknown），Tinycast 据此放行“只看、且路径都在文件夹内”的命令；
  - 不加指令时，模型会用 `printf >>` 改文件。指令里要求用 `apply_patch` 后，改动以 `fileChange` 补丁的形式到达，`item/started` 带 diff，授权请求的 `itemId` 和这个 item 的 id 一致；
  - 拒绝后本轮继续；只读沙箱下模型不会尝试写入；
  - app-server 重启后 `thread/resume` 能接上；未知线程返回 `no rollout found`，于是新开线程。

仍待在界面里实测：卡片的键位和焦点、排队计数、redirect 之后自动发送那句话、Codex 删除（补丁里的 delete）的卡片。

已知限制：

- 文件夹路径里有符号链接时（如 `/tmp` → `/private/tmp`），Claude 报上来的是解析后的真实路径，Tinycast 会把它当成文件夹外。结果是多问，不会少问。
- 删除聊天时，CLI 自己存的会话（`~/.claude/projects`、`~/.codex/sessions`）不会一起删。

## 5. 切片 3 落地情况

已实现。Debug 构建无新警告，lint 干净；`ai-chat-test` 359 个、`agent-test`、`settings-file-test`、`settings-backup-test` 通过。界面还没有实际操作过。

| 层 | 文件 |
| --- | --- |
| 状态 | `AIChatSurfacesState.waiting`（等待确认的对话，窗口里那个排第一）；`AIChatState.onReplyEnded`（自己结束时报告完成或失败，读者停止的不报告，命名也挂在这上面） |
| 提醒 | `AgentWaitingHUDController` + `AgentWaitingHUDView`（独立 presenter，位置在消息胶囊上方）；`HUDCapsule`（所有胶囊共用的表面）；`MenuBarLabel` 的蓝点和 `MenuBarMenu` 的“查看…中的请求”；侧边栏行的蓝点；`ToolbarItemIndicator`（侧边栏按钮的系统角标） |
| 侧边栏 | `AIChatSidebarPeek`（每个窗口一份：是否收起、宽度、是否滑出）；`AIChatSidebarPeekEdge`（左缘悬停和浮层）；`AIChatSplitViewController`（KVO 同步收起状态，滑出时 ⌘B 原地固定） |
| 设置 | `aiSidebarPeek` / `ai.sidebarPeek`，默认开；和其他 AI 设置一样不进备份 |

和交互稿不一致的地方：

- 侧边栏按钮上的提示用系统的 `NSItemBadge.indicator`，是红点，不是蓝点；行内、菜单栏和 HUD 是蓝点。和 Mail 一致：按钮和图标上的角标是红色，列表里的未读点是蓝色。SDK 把 `indicator` 声明成了可变的 static，Swift 6 下要 `@preconcurrency import AppKit`，所以单独放在 `Platform/ToolbarItemIndicator.swift`。
- 等待的 HUD 文案是“Claude Code 等待确认 · 运行命令”，多个对话同时等待时是“2 个对话等待确认”；悬停时手形变成 ✕，点一下收起，直到出现新的请求。AI Chat 窗口是 key 时不显示，由侧边栏的点和按钮角标提示。
- 完成提示只针对 agent 对话，并且只在读者没看着这个对话时出现；失败也会提示（红色“未能完成”），交互稿只写了完成。
- 滑出的侧边栏不是纯玻璃：下面垫了窗口底色，否则转录的文字会透出来，和上下文卡片的做法一样。它从窗口顶部开始，四周留 8pt，圆角 18。
- 只有窗口是 key 时才会滑出；按 Esc 立即收回；固定时不再播放展开动画，真正的侧边栏直接出现在原地。

已知限制：

- 侧边栏宽度在第一次展开前未知时，按最小宽度 240 滑出。
- 在滑出的侧边栏里搜索或重命名时，浮层不会因为指针离开而收起；输入结束后，要等指针再移动一下才收回（或者按 Esc）。

## 6. 内容呈现：状态行、工具详情和展开

已实现。展开卡片在离屏渲染里核对过深浅两种外观；在 app 里还没实际点过。

- **状态行**：所有对话（窗口和 Quick AI）在回复进行中，末尾都有一行"正在处理… / 正在思考…"加已用时间。末尾已经在动的时候（步骤在运行、推理或搜索还在到达、正文在输出）不显示；agent 对话在正文下面也保留，因为它写下一条命令时可能停很久。推理摘要有加粗标题时，折叠行的标题用它。所有 Codex 回合都请求 `summary: "auto"`。
- **命令**：Codex 的 `/bin/bash -lc '…'` 按 shell 规则拆词后只显示里面的脚本，行和授权卡片都一样。退出码非零的写"已运行 … · 退出码 N"，没有退出码的失败写"未能运行 …"。
- **数据层**：`ChatToolDetail` 存完整输入（命令、路径、模式或 unified diff）、Claude 对命令的说明、输出（末尾 16K 字符，从行首开始）和退出码，表是 `message_tool_details`。
- **展开**：有详情的工具行可以点开，下面是和回复里代码块同款的卡片：说明、输入和复制按钮、分隔线、输出。编辑显示成 diff，文件按对话文件夹里的路径各写一行，行上显示"+N −M"。长内容只显示前 12 行（命令输出显示最后 12 行），点"显示全部"展开，转录里不再套一层滚动。
- **不枚举工具名**：工具名只用于显示（标题、图标、把 Edit 拼成 diff），而且只覆盖我们自己开放的那几个：Claude 用 `--tools` 白名单，Codex 用协议条目类型。MCP（三条路）、新工具、改了名的字段，一律存原始 JSON 输入和文本结果。

实测（2026-10-19）：

- Claude 2.1.303：Bash 成功时 `tool_result.content` 就是输出（stderr 也在里面）；失败时 `is_error: true`，内容第一行是 "Exit code 1"。没有单独的退出码和耗时字段。`tool_use.input.description` 是 Claude 自己写的一句说明。
- Codex 0.162.1：`commandExecution` 完成时带 `aggregatedOutput`、`exitCode`、`durationMs`（快命令是 0）、`cwd`、`commandActions`；没有收到 `item/commandExecution/outputDelta`。`turn/start` 不传 `summary` 时，连"开始推理"的条目都没有；传 `auto` 或 `detailed` 后有这个条目，但 gpt-6.1-sol 不给摘要文字。
