# Capture 一期 Spec

状态：设计基线 v0.2，2026-09-23。已纳入交互便捷性评审；长截图属于一期，实施与验证状态见 Plan。

配套：[实施 Plan](capture-plan.md) · [交互设计](capture-interaction.md) · [可点击原型](capture-prototype/index.html)。

2026-09-24 范围扩展：完整能力目标与原位操作改版见[统一工作区方案](capture-unified-workspace.md)。本文保留一期交付基线；截至 2026-09-29 的图片增强、录制、视频与原生证据见[落地记录](capture-workspace-implementation.md)。新增能力不改变一期未关闭的验收项。

## 1. 目标

从 Tinycast 的搜索、全局快捷键或剪贴板图片进入截图工作流，完成捕获、标注、贴图、取字、翻译和输出。
滚动长截图和普通截图进入同一个编辑器，使用同一套标注、输出及历史规则。

一期采用原生集成，不依赖另装 Macshot，不通过模拟点击或 Macshot URL scheme 实现核心能力。
Macshot 是算法、交互与回归样本的参考；移入代码时保留来源和适用许可。

## 2. 已确认范围与设计决策

| ID | 一期要求 | 明确边界 |
| --- | --- | --- |
| CAP-01 | 区域、窗口、当前屏幕截图 | 可在任意显示器启动；一期选区限单屏，不做跨显示器合成 |
| CAP-02 | 滚动长截图 | 纵向、横向；单次固定一个轴；手动滚动和主动开启的自动滚动 |
| CAP-03 | 常用标注 | 选择/移动/缩放、箭头、矩形、椭圆、文字、画笔、编号、打码、撤销/重做 |
| CAP-04 | 图片编辑 | 裁剪、缩放查看；打开剪贴板图片；历史中重新编辑 |
| CAP-05 | 贴图 | 截图、编辑结果、剪贴板图片；拖动、缩放、透明度、关闭和返回编辑 |
| CAP-06 | OCR | 截图取字、编辑结果取字、长图取字；本地识别；可选择或修正结果 |
| CAP-07 | 截图翻译 | OCR 文本交给现有 Translation；继续使用 Apple/AI 配置 |
| CAP-08 | 输出 | 复制最终 PNG、另存 PNG/JPEG/HEIC；成功反馈和失败恢复 |
| CAP-09 | 历史 | 最终图片、缩略图、重新打开；可选择保留原图和可编辑标注 |
| CAP-10 | Tinycast 接入 | 命令、别名、快捷键、设置搜索、权限入口、渠道隔离 |

设计默认值：纵向长截图、手动滚动、复制后关闭编辑器、PNG、原始像素分辨率、关闭鼠标指针捕获。
长截图方向在开始前可改为横向，捕获中改变方向需要重新开始，已捕获内容可先保留。

二期：美化背景、自动 PII/人脸遮盖、OCR 原位覆盖翻译、多张图片自由拼版、跨屏合成、QR 功能。
三期：录屏、音轨、视频时间线、GIF、云上传。上述能力不以隐藏开关进入一期。

不迁入 Macshot 的 AppDelegate、全局快捷键管理、翻译服务、Sparkle、上传账户、旧系统捕获分支或旧历史迁移。
一期不导入 Macshot 历史，也不改它的安装、配置或权限。

## 3. 产品入口

以下标识为拟新增项，实施时沿用 `CommandID` 的穷举映射。

| CommandID / raw value | 标题 | 行为 |
| --- | --- | --- |
| `captureScreenshot` / `command:capture-screenshot` | Capture Screenshot | 区域选择；Space 切换窗口选择 |
| `captureFullscreen` / `command:capture-fullscreen` | Capture Full Screen | 捕获触发时鼠标所在屏幕，进入编辑器 |
| `captureScrollingScreenshot` / `command:capture-scrolling-screenshot` | Capture Scrolling Screenshot | 选择滚动区域，确认方向，开始手动捕获 |
| `captureText` / `command:capture-text` | Capture Text | 选择区域后直接识别并显示取字面板 |
| `captureAndTranslate` / `command:capture-and-translate` | Capture & Translate | 选择区域、OCR、打开 Translation |
| `editClipboardImage` / `command:edit-clipboard-image` | Edit Clipboard Image | 读取图片或可解码本地图片文件，进入编辑器 |
| `pinClipboardImage` / `command:pin-clipboard-image` | Pin Clipboard Image | 创建贴图；没有图片时给出 HUD |
| `captureHistory` / `command:capture-history` | Screenshot History | 打开截图历史 |

- 条目类别均为现有 `.command`；归属只在 `SettingsTab.ownedCommands` 的 `.capture` 声明。
- 不预占全局快捷键。由现有 HotKeyManager 录制、冲突检测和分发；不注册第二套热键。
- 剪贴板图片的 Actions 增加 Edit Image、Pin Image、Extract Text、Translate Text，进入相同 coordinator。
- 重复触发截图命令不堆叠遮罩；选区中聚焦现有会话，长截图中停止并进入当前结果的编辑器。
- 普通截图未标注/未裁剪时，新截图或关闭直接结束临时文档；有实际编辑或已经拼成长图时，先确认保留/丢弃/取消。贴图可继续存在。

## 4. 捕获和窗口生命周期

### 4.1 普通截图

1. 记录触发来源、目标应用、显示器和会话 ID。启动时不枚举屏幕、不请求权限。
2. 权限未就绪时显示 Tinycast 自有说明；用户点击授权后调用系统权限流程。失败保留命令意图，但授权返回后需点击重试，避免意外截屏。
3. 全局热键路径在显示自身窗口、切换焦点前取得画面，保留原应用短暂菜单；从 Launcher 进入时先完成 palette 隐藏，再捕获。
4. 使用 macOS 26+ ScreenCaptureKit。窗口选择使用内容过滤；自身遮罩、贴图及控制条不得出现在输出。
5. 拖动选区，显示真实像素尺寸；反向拖动、屏幕负坐标、混合 1×/2× 显示器均由纯几何策略处理。
6. 普通选区默认主动作是复制，Return / Command-C 直接输出并返回原应用；编辑为次动作。OCR/翻译命令直接进入文本工作流。Escape 放弃未确认选区且不写剪贴板。

一期不自动捕获所有屏幕的全分辨率快照。活动屏幕显示冻结图，其余屏幕只负责入口切换和遮罩。
切换目标屏幕重新取得该屏幕快照；不会宣称多屏画面来自同一时刻。

### 4.2 窗口职责

| 表面 | 所有者 | 焦点与关闭规则 |
| --- | --- | --- |
| `CaptureOverlayController` | CaptureCoordinator 的会话 | 临时非激活 NSPanel；取消、成功交接、锁屏均回收 |
| `ScrollCapturePanelController` | CaptureCoordinator 的会话 | 控制条在选区外；滚动区域鼠标穿透；点击目标应用不取消 |
| `CaptureEditorController` | CaptureCoordinator | 一次一个文档；独立可调整 NSWindow；失焦保留；关闭处理未保存内容 |
| `CapturePinController` | CaptureCoordinator 的有限集合 | 非激活浮窗；失焦保留；关闭释放该贴图的图像和文档租约 |
| Translation 文本面板的 Capture 会话 | TranslationCoordinator；CaptureCoordinator 保留来源 | 取字/修正原文/翻译共用同一面板；失焦保留，显式关闭才释放 |
| 截图历史 | CaptureCoordinator / palette | 复用 palette 列表语言；选择条目后在独立编辑器打开 |

所有长期状态从 AppCore 持有。编辑器使用现有 ActivationPolicy 的 windowDidOpen/Close；不自行切换 Dock 策略。
会话保存原应用用于结束时恢复焦点；用户已经主动切换到其他应用时不抢回旧应用。
对话框经 DialogController，通知经 HUDPresenter。标准文件选择仍使用异步 NSSavePanel，不使用 NSAlert 或 NSPopover。

## 5. 长截图契约

长截图是一期发布条件；仅普通截图可用不算一期完成。

### 5.1 捕获行为

- LC-01：开始前选择区域和轴，默认纵向。区域可位于任意单个显示器内，绑定目标应用、窗口和该屏幕映射。
- LC-02：手动模式只要求屏幕捕获权限。用户在原页面滚动，控制条和预览不覆盖捕获像素，也不拦截滚轮。
- LC-03：自动模式由用户本次点击开启；如需合成滚动事件，单独请求 Accessibility。拒绝时保留手动模式和已有片段。
- LC-04：自动滚动只向已确认的目标发送事件。目标移走、最小化、被其他窗口遮挡、显示器断开、锁屏或应用切换时立即暂停；重新确认后才继续。
- LC-05：只将稳定且可对齐的新内容纳入结果。滚动距离过大、低纹理、动画或布局重排导致无法可靠对齐时暂停，保留最近有效片段。
- LC-06：固定页头/侧栏只保留一次；滚动条不参与配准，输出不重复其轨迹。不能确定固定区域时暂停并允许用户重选较窄区域。
- LC-07：重复画面不增加长度；倒向滚动不追加重复内容，也不撤销已拼接片段。连续无进展只提示“没有发现新内容”，不宣称已到页面底部。
- LC-08：暂停不丢已有内容；继续时先和最后一个已接受片段重新匹配，失败不能强行拼接。
- LC-09：完成使用最后一个已接受片段，进入相同编辑器。拼接失败时可“保留已有内容”或“重新选择”；不自动丢弃。
- LC-10：取消先停止采样和自动输入。有新增片段时询问丢弃或保留；只有初始帧时直接退出。显式丢弃才删除本次临时数据。

捕获中始终显示方向、已经获得的像素长度和暂停/完成；不显示虚构百分比或页面总长度。
手动捕获不承诺在原应用持有键盘焦点时拦截 Enter/Escape：控制条获得 key focus 时它们才生效，按钮始终可用。
已绑定的 Tinycast 捕获热键可以作为不依赖页面焦点的完成入口。

### 5.2 拼接管线

`ScreenCaptureKit → 稳定帧判定 → 配准 → 重叠/固定区域策略 → 新条带 → 文件分块 → 低分辨率预览`

- 帧采样串行，最多一组处理中的相邻帧；慢处理时丢弃尚未提交的候选帧，绝不无限排队。
- 使用独立 RGB 差异和几何校验验证配准结果，不能仅凭 Vision 返回了位移就追加。
- 坐标分别命名：屏幕 points、捕获 pixels、文档 pixels、视图 points；整数裁剪只在像素边界发生。
- 每个片段记录来源矩形、目标偏移、重叠裁剪和会话 revision；相同 revision 只提交一次。
- 输出在磁盘上追加不可变条带/分块。禁止每次滚动重建一张不断增长的完整 NSImage。
- 预览只显示有界缩略图；编辑器按视口读取分块。标注、裁剪和撤销存参数，不复制全图。

### 5.3 一期资源界限

以下是待 G0 验证的初始安全上限，不是已达到的性能指标：

| 项目 | 初始设计值 | 到达上限后的行为 |
| --- | --- | --- |
| 单张最终图 | 64,000,000 pixels，任一边不超过 30,000 px | 停止继续追加，允许保存已有内容；明确说明上限 |
| 常驻解码 tile | 1024 × 1024 RGBA，最多 4 块 | LRU 释放；缩放预览单独有界 |
| 同时编辑文档 | 1 | 未编辑的普通截图直接替换；实际编辑或长图先确认 |
| 同时贴图 | 3；显示分辨率预览 | 超限提示先关闭一张；不加载三张完整原图 |
| 捕获处理队列 | 1 个候选任务 | 施加背压，不累计过期帧 |

上限需要在开始前做尺寸预检；不可降低分辨率后仍声称“原始尺寸”。文件编码和剪贴板写入同样纳入预算。
JPEG/HEIC 编码如在长图压力样本下超预算，先禁用该尺寸对应格式并解释原因；PNG 是长截图必须通过的输出路径。

## 6. 编辑、输出、贴图

### 6.1 编辑模型

`CaptureDocument` 保存稳定 ID、像素尺寸、色彩空间、原图/分块引用、标注、裁剪和 revision。
纯值模型不包含 NSImage、NSColor、NSBezierPath 或 NSTextView；颜色采用 RGBA，平台渲染在 Service/UI。
每次编辑操作形成可撤销的值变更；拖动结束才提交一个撤销项。文字输入法组合期间不提交标注。
捕获本身不等于编辑：普通截图无标注/裁剪时 Escape 或关闭直接结束；长截图保留退出确认。
普通图默认适合窗口，纵向长图默认适合宽度，横向长图默认适合高度；长轴可滚动，整图概览为次动作。
文字编辑器持有自己的 undo manager；结束编辑后清空文本 undo，画布 undo 不引用已释放的 NSTextView。

打码默认实色覆盖，可切换像素化；两者作为显式标注保存。导出使用已经合成打码的结果。
重开缺损的可编辑原稿时只能展示已保存的最终图，不能遗漏遮盖后露出原图。

### 6.2 输出事务

1. 复制/保存开始时固定 document ID、revision 和输出配置，后台按这一快照渲染。
2. 复制成功后才更改剪贴板。保存先写同目录临时文件，再原子发布，失败保留旧文件与当前编辑状态。
3. 输出期间允许取消；取消和最终发布有单一决策点。发布已成功不能随后报“已取消”。
4. 默认复制后关闭，必须等剪贴板成功。保存成功保留编辑器，方便继续处理；关闭提示只针对输出后的新修改。
5. 外部应用在输出过程中写入剪贴板时，由用户本次 Copy 的明确动作完成最终写入；不进行后台 OCR 结果自动覆盖。
6. 复制调用统一的 Capture 输出入口，与 ClipboardManager 的 mutation handshake 协作，显式按现有启用/排除策略记录一次，内部 marker 防止轮询重复。
7. Clipboard 功能关闭时仍能复制，但不能由 Capture 私自打开历史数据库或启用索引。
8. 图片文件 promise/延迟 pasteboard provider 的 backing file 必须活到约定交付完成；不在编辑器关闭时提前删掉。

图片输出使用 PNG/JPEG/HEIC/AVIF；2026-09-29 用户批准官方 libwebp 静态组件的依赖例外，增加 WebP 文件导出。
默认、Copy 和历史最终图仍用 PNG，不引入 Sparkle。新截图历史属于 Capture，Clipboard 接收用户复制的最终图。
WebP 的透明度、色彩、尺寸和构建约束见 [独立决策](capture-webp-decision.md)。
无需在一期改造 ClipboardItem 的 schema；“重新编辑既有标注”从 Capture 历史进入，普通剪贴板图片按平面图片打开。

### 6.3 贴图

显示当前 revision 的冻结结果，后续编辑不悄悄更新已贴图片。贴图不会仅因打开就写剪贴板或历史。
拖动移动；滚轮/捏合围绕指针缩放；菜单提供透明度、复制、编辑、关闭；内容默认不穿透，避免无法找回控制。
“编辑”新开该贴图的独立 revision，不转移或销毁贴图。关闭最后一个引用后释放资源。

## 7. OCR 与 Translation 的边界

- 主动 OCR 独立于“剪贴板文字索引”开关。显式用户任务优先；暂停并等待背景识别退出后启动前景任务，完成后按原设置恢复。
- 将现有 OCR helper 的公共识别部分迁到 `Platform/TextRecognition/`，更新两个调用者和 XcodeGen target；不保留旧名字的兼容 wrapper。
- `searchIndex` 保留现有低成本策略；`captureText` 按原分辨率有重叠分块，不能把整张长图压到现有约 2048² 像素预算后再识别。
- helper 接受文件/分块引用与 policy，输出受限 JSON：request ID、revision、文本、文字框和 `truncated`。只按重叠位置去重，不能删除不同位置的同文内容。
- 初始上限：文本 32,000 UTF-8 bytes、1,000 个文字框、响应 1 MiB。到限返回显式部分结果，面板标注“仅识别部分内容”，提供缩小范围继续识别。
- OCR 基于当前合成结果，已打码区域不从原图重新取字。后台索引也不能索引 Capture 保留的原始未遮盖数据。
- 新会话、修订、关闭使旧结果失效；先取消并回收 helper，再释放输入租约。helper 崩溃可重试，错误不写正文。
- Translation 增加 `open(text:source:)`，source 标识 `.capture(documentID, revision)`；进入时清空旧回填 target，不再次读取前台选区。
- 原选区翻译的 `open()` 保持既有语义。截图来源只复制译文，默认没有 Insert/Replace。
- `.capture` 的取字/翻译属于同一稳定文本会话，失焦不取消、不清空原文或结果；无需先置顶。显式关闭才取消任务并释放。取字阶段允许复制和修正，点击翻译后在同一面板呈现结果。
- 继续使用现有默认 Apple 和独立 AI route，无自动 provider fallback，不重复保存 API key。
- 现有翻译输入上限为 12,000 UTF-8 bytes。长图 OCR 超限时先打开取字面板，允许选择/编辑到上限内后翻译，不静默截断或自动拆多次计费请求。
- Apple 缺语言包、Translation 关闭、AI 未配置/失败/截断均有现有恢复入口；保留本次原文。

## 8. 历史、权限与设置

### 8.1 数据归属

- 渠道根目录使用 AppPaths 和 Bundle.main.bundleIdentifier，Dev 与正式版完全隔离。
- 已提交截图及用户选择保存的草稿放 `Application Support/<bundle>/captures/`；可重建缩略图和临时处理数据才放 Caches。
- 历史默认保留最终图 7 天，容量上限 512 MiB；按最旧条目回收，有活动编辑/贴图/导出引用的条目延后清理。容量是磁盘上限，不是内存预算。
- 默认不保留可编辑原图；可在 Capture 设置开启“保留可编辑原稿”，说明“包含原图和标注，也包含打码前内容”。此开关不随备份导入。
- 关闭原稿保存时，历史仍可打开平面结果添加新标注，不能撤销先前已经合成的打码。开启后可编辑原标注；两种模式在历史中有清楚标识。
- 自动历史只在用户成功复制或保存之后提交。用户显式“保存草稿”可以单独持久化可编辑文档；纯取字/翻译不自动保存截图。
- 历史写入失败不得把已经成功的 Copy/Save 报成失败；显示“已复制，历史保存失败”并保留重试入口。
- 草稿/历史使用不可变 revision 和原子 manifest。序列化失败不替换已提交版本；没有可验证索引时不能清扫可能属于用户的文件。
- 退出先取消采样/自动滚动，再处理未保存编辑和未完成输出；不取消已经发布的结果、不直接丢弃保存中的源文件。

### 8.2 设置

新增 Capture pane，使用标准 grouped Form 和 SettingsSearchCatalog/SettingsAnchor：

| 分组 | 项目 / 默认 |
| --- | --- |
| 功能 | Enabled = true，仅注册入口；启动不采样、不枚举、不授权 |
| 输出 | 格式 PNG；原始尺寸；复制后关闭 = true；包含鼠标 = false |
| 长截图 | 默认纵向；手动启动；自动滚动速度中等，仅显式按钮开始 |
| 历史 | 保留 7 天；最多 512 MiB；保留可编辑原稿 = false |
| 快捷键 | 上述命令复用现有录制器，默认无绑定 |
| 权限 | Screen Recording 状态/设置入口；自动滚动所需 Accessibility 状态 |

设置备份只包含显示、格式和方向等无授权偏好。原稿留存开关、自动滚动运行状态、TCC 状态、截图/草稿/识别文本不进入设置备份。
Capture 关闭后入口隐藏、采样和任务停止；未保存编辑先完成保存/丢弃流程，取消关闭请求则维持开启。

## 9. 架构与实施边界

```text
AppCore
  └─ CaptureCoordinator
       ├─ CaptureSession / ScrollCaptureSession
       ├─ CaptureOverlayController / ScrollCapturePanelController
       ├─ CaptureEditorController / CapturePinController
       ├─ CaptureRepository / CaptureOutputService
       └─ TextRecognitionWorker → TranslationCoordinator.open(text:source:)
```

实现位于 `Features/Capture/{Model,Service,UI,Settings}`。Model 持有文档值、坐标转换、拼接决策、撤销、预算和状态机。
Service 持有 SCK、配准、分块文件、渲染和输出；UI 持有 AppKit 控制器和 SwiftUI 表面。
AppKit 只承担真实需求：全屏覆盖、鼠标穿透、画布 hit testing、文字 responder 和独立窗口；不把全部设置改写为 AppKit。
Views 经 `@Environment(CaptureCoordinator.self)` 调用动作，不引入第二个 singleton/actor。
重工作使用显式 nonisolated worker 与受持有、可取消的 Task；SDK 回调只在必要边界适配。

捕获与编辑在主进程，OCR 使用共享 TextRecognitionHelper；WebP 使用短生命周期 CaptureWebPHelper，
已取得 20 轮同时总 RSS、退出回落和像素一致性证据，见 [WebP 决策](capture-webp-decision.md#helper-原生-20-轮验收)。
录制保持现有进程内实现，基础全屏录制的 20 轮资源复验已通过；设备增强场景仍待验。
不能仅为了把数字移到另一个进程就宣称满足内存标准；
新增进程涉及 TCC、签名、退出和文件租约，必须单独记录实验证据。

### 内存和性能 Gate

2026-09-29 用户明确要求替换统一 100 MB 门槛，采用以下 v3 预算。MB 均为 1,000,000 bytes。
机器可读规则见 [memory-policy-v3.json](capture-evidence/memory-policy-v3.json)，采样和判定使用
`python3 Scripts/capture-memory.py`。这是资源验收标准，不在用户点击 Copy 时按整机 RSS 拒绝小图。

| 场景 | 主进程与本应用 helper 的同时 RSS 总和上限 |
| --- | --- |
| 冷启动空闲，无采集、OCR 或媒体任务 | 160 MB |
| 普通区域、窗口、全屏截图及复制/导出 | 300 MB 峰值 |
| 1600 × 30000 长图、OCR、三张贴图及图片编辑/输出组合 | 512 MB 峰值 |
| 当前支持尺寸/帧率的录制、播放及 MP4/GIF 导出 | 600 MB 峰值 |

依据：普通截图 20 次实测峰值 268.5 MB、关闭五秒后 196.2 MB；2026-09-29 无诊断工具的单轮
48 MP + 三贴图 + OCR + PNG Copy 同时峰值 329.1 MB。该单轮关闭标记晚于实际关闭，
188.3 MB 是观察标记五秒后的值，不能独立关闭精确五秒 gate。此前长图/OCR 与三贴图/OCR
诊断峰值分别约 326.5 MB、345.1 MB，后两项有诊断工具干扰，必须补做无干扰实测。
录制预算同时覆盖 SCK、待编码和合成缓冲（每组最多三帧）；3840 × 2160 的单帧 BGRA 约 33.2 MB，
再加应用与媒体框架常驻。600 MB 为固定上限，不允许队列随时长增长。
基础全屏录制已完成 20 轮，峰值 339.4 MB、最高五秒回落 239.7 MB、稳定增长 4.2 MB，
见[实测报告](capture-evidence/video-native-20-report-20260929.json)。麦克风、摄像头及其他设备组合仍须分别验收。

2026-09-29 WebP 实测后修正为 v3：最初 v2 的图片 400 MB / 关闭 250 MB 基于流式 PNG、OCR 与贴图，
没有覆盖新增 libwebp 的高熵工作集。4 MP 无损/有损/PNG 原生保存组合观测为 393.4 MB 峰值、
关闭五秒 276.6 MB；回收实验为 406.2 / 277.9 MB，未改善，实验代码已撤回。
将图片峰值定为 512 MB，为实测最坏值留约 26% 余量；图片/视频关闭上限定为 300 MB 且冷基线 +160 MB。
普通截图仍为 300 / 250 MB / 冷基线 +100 MB。仍保留 4 MP 非流式编码上限、helper 总和、全部关闭对象释放、
20 次循环 ≤10 MB 增长与 P95。旧 v2 失败原样保留；新标准下单轮数值达标不能替代完整循环验收。
依据和撤回实验见 [WebP 证据](capture-evidence/webp-20260929.json)。

- 主进程 RSS、helper RSS、同一采样时刻的总和必须分别报告；不能把各进程不同时间的峰值相加。
  physical footprint 只作诊断，不替代 RSS。记录硬件、OS、构建、尺寸、帧率和辅助设备状态。
  `resourcePassed` 只在冷基线、全部回落、helper 退出与 20 轮增长数据完整后判定；缺项用 null。
- 每个独立场景重启本 checkout 的 Dev，等待空白 launcher 完整显示并空闲至少五秒，再记录同一 UI 状态的冷基线。
  启动前台切换和尚未显示 launcher 的样本单独标记，不能混入冷基线中位数；200 ms 采样，禁止同时跑构建、harness、heap 或 debugger。
- 场景保留：5K 单屏、混合 DPI 双屏切换、48 MP 长图、3 张贴图、OCR、PNG 编码、复制后粘贴、录制/视频输出。
- 功能未使用时不增加后台任务。关闭全部相关窗口、终止 helper 和采样后，五秒内普通截图回到冷基线 +100 MB 且不超过 250 MB，
  图片与视频回到冷基线 +160 MB 且不超过 300 MB；对应场景的两个限制都要满足。应用拥有的源文件租约和 Capture 对象必须释放，不能只看 RSS。
- 普通截图、长图/OCR/贴图和录制分别跑 20 次完整操作。前五次预热，比较第 6–10 次与第 16–20 次
  关闭五秒后的 RSS 中位数，增长 ≤10 MB；每轮峰值和回落也要分别达标。未采足或时间边界不明确记为待验。
- 交互目标：权限已就绪时入口到可选区域 P95 < 500 ms；候选片段稳定后到预览更新 P95 < 500 ms；实际采样数量与硬件写入报告。
- 不能假定 ImageIO 的“添加图像”API 等于逐行有界编码；PNG、JPEG/HEIC、pasteboard 都单独测。
- 耗时以应用内 `CapturePerformance` 事件计时，至少 20 个成功样本，用 nearest-rank P95；
  `selection-ready` 从命令处理入口到可选区域已展示，`scroll-preview-ready` 从稳定判定到新预览提交。
  这不包含系统显示器最终扫屏耗时；电脑操作工具的 AX/通信延迟不计作产品耗时。
- 五秒回落使用应用内关闭日志时间，`Scripts/capture-memory.py report --native-closures --log`
  读取同一 PID 的 ndjson 事件；普通截图保存后复制用 `--closure-event copy-closed`，避免将其他关闭动作计入循环。
  三贴图组合关闭编辑器和 OCR 后，以 `--closure-event pins-closed` 的最后贴图关闭事件为准；其他完整工作区用 `workspace-closed`。
  手工标记迟到时不能替代精确边界。短生命周期编码 helper 可使用 `--interval 0.02`
  提高采样频率，并报告实际采样间隔与观测峰值。
- G0 不通过时继续缩减常驻像素与排队；不得删除长截图或改用进程增量来标记一期完成。

## 10. 验收矩阵

| ID | 通过条件 | 必须提供的证据 |
| --- | --- | --- |
| AC-01 | 命令可搜索/绑定；启动无采样/授权；普通选区直接复制，无编辑新图可直接取消/重截 | 命令/会话 harness + Dev 原生操作 |
| AC-02 | 单屏区域/窗口/全屏尺寸正确；负坐标和混合 DPI 无偏移/黑边 | 几何 fixture + 实际外接屏记录 |
| AC-03 | 手动与自动、纵向与横向完成长截图；暂停可继续；初次打开按短轴适配，正文可直接检查 | 拼接 fixture + 浏览器/PDF/原生列表实测 |
| AC-04 | 固定区域只出现一次；无重复行/遗漏；不可靠时暂停保留 | 已知坐标的编号/文本 fixture；1 px 拼接误差上限 |
| AC-05 | 取消、屏幕断开、目标切走/移动、权限撤销不继续采样或输入 | 生命周期测试 + 对应原生验证 |
| AC-06 | 所有常用标注可选中修改、撤销/重做、裁剪；文本 IME 不误提交 | 标注/几何/文本测试 + 键盘操作 |
| AC-07 | Copy/Save 输出同一 revision；失败不损坏目标文件；取消无半成品 | 像素/文件事务测试 + 独立解码核验 |
| AC-08 | 贴图失焦保留，三个贴图可释放，返回编辑保留内容 | 原生操作 + 生命周期/内存记录 |
| AC-09 | 长图小字不因整图缩小丢失；重叠去重不删除真实重复文本 | 固定中文/英文/混合长图 corpus + Vision 实测 |
| AC-10 | 截图翻译复用配置、清空回填目标；超 12 KB 不截断；跨应用核对再返回时原文/译文/任务保留 | Translation focused harness + 实际引擎记录 |
| AC-11 | 历史平面/可编辑两种模式语义正确，缺侧车不露原图 | 仓储故障注入 + 重启/重开验证 |
| AC-12 | Clipboard 关闭、敏感来源排除、内部 marker 不造成重复记录 | 私有 pasteboard fixtures + 集成检查 |
| AC-13 | Light/Dark、Interface Size、VoiceOver 和焦点路径符合交互稿 | 明亮桌面的原生截图/录屏及人工结果 |
| AC-14 | 内存、释放和交互指标通过 G0 及完整功能复测 | baseline/峰值/回落数值、采样脚本和原始报告 |
| AC-15 | 完整 harness、lint、Model 纯度、Debug 零新增 warning | 本轮提交对应日志；Release 检查并发/编码路径 |

Fixtures 通过不替代真实 SCK、硬件显示器、系统权限、Apple 语言包或 AI 服务验证。
HTML 原型只证明设计分支可探索，不作为以上原生功能通过证据。

## 11. 源码依据与剩余决策

核对基线：Tinycast HEAD `5a78753` + 当前未提交 Translation；Macshot HEAD `a93bf38`。

- [Tinycast CommandID](../../Tinycast/Features/Launcher/Model/CommandID.swift)、[CommandCatalog](../../Tinycast/Features/Launcher/Model/CommandCatalog.swift)。
- [TranslationCoordinator](../../Tinycast/Features/Translation/UI/TranslationCoordinator.swift)：保留前台选区入口，并新增已有文本/截图来源入口，清空回填目标和保留来源租约。
- [TextRecognitionExtractor](../../Tinycast/Platform/TextRecognition/TextRecognitionExtractor.swift)、[project.yml](../../project.yml)：当前 OCR helper 和缩放预算。
- Macshot 本地参考：`macshot/Capture/ScrollCaptureController.swift`、`ScrollFrameAnalyzer.swift`、`UI/Tools/AnnotationToolHandler.swift`、`Services/HistoryStorage.swift`。
- [Apple SCScreenshotManager](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager)：以官方 API 和当前 SDK 签名作为实现依据。
- [Apple 图像输出说明](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/ImageIOGuide/ikpg_dest/ikpg_dest.html)：不提供本项目内存预算的保证，编码需实测。

G0 已选择系统 zlib 逐行 PNG、8 MB 编码数据的复制上限和超限原尺寸保存路径；WebP helper 决策已落地。
48 MP 长图/OCR/三贴图/PNG 组合与单独 WebP 均有 20 轮资源通过证据。最大捕获帧、5K/混合倍率、
大图跨应用交付完整矩阵及录制资源仍待现场验证；不将局部通过记为 G0 全部完成。
最新决策见 Plan，未关闭条件集中见[交付状态](capture-delivery-status.md#一期尚未关闭的验收)。


## 12. 实施记录

v0.3 已把上述原生能力接入命令、设置和 AppCore，详见 [实现说明](../features/capture.md) 与
[验收记录](capture-acceptance.md)。本轮全量 harness 82/82 通过，原生导入、遮盖、OCR、AI 翻译、PNG 保存与
历史回开已有证据。本轮补充 TextKit、JPEG/HEIC 像素、预览接缝和中断监听测试。用户已授权两项权限；修复 Dev 旧签名授权记录后，
真实 SCK 选区和取消已运行。2026-09-24 新增编辑器 Copy → Preview 解码和历史单次接收证据；
普通选区 Return 直接复制也已通过 Preview 接收、再导出和逐像素一致性校验。
实时滚动现场先后发现系统光标及 Dock 全屏表面被算作遮挡，修复及回归通过；
长截图的 SCK filter 与遮挡检查现在共用应用排除名单。纵向手动样例已导出 1500 × 3276 PNG，
独立解码、连续编号 002–024、跨拼接处的 142 像素行间距和历史单次接收均通过；
临时签名重编译会使录屏授权失效。经用户批准，当前 Dev 和 OCR helper 已改用固定的本地签名身份；
严格签名校验、真实选区和两个不同 CDHash 构建之间的录屏/辅助功能授权留存检查通过。
前台交接与系统弹窗阻塞已解除。自动事件改走系统 session event 路由后，真实纵向自动输出 1500 × 3880，
063–089 连续、行距 142 像素。横向自动输出 3920 × 760，手动输出 3420 × 760，列号逐行连续、列距 446 像素。
四图各匹配一条历史，横图首次按高度适配、保存后关闭无额外确认。
启动暂停分别定位到真实工具浮窗遮挡和屏上清单漏掉自身应用；后者已通过完整清单建立排除集合修复，
目标窗口仍要求屏上可见。完整 corpus、固定区域和中断矩阵仍未关闭，G3 保持未完成。
fork 应用身份、Release 构建与社区安装版替换尚未实施，证书本身不代表一期验收完成。

此前实现记录没有修改一期范围；2026-09-29 资源预算已按用户要求更新为上面的 v3，不能据此宣称 CAP-01…CAP-10 已交付。8 MB 压缩 PNG 的
复制上限是有界交付保护，不是完整资源能力的测量结论；原尺寸 PNG 文件输出保留为可用恢复路径。
普通 Copy 不再以整款 app 当前 RSS 决定是否可用，避免已有基线超标导致小图也永久不可复制。
原 100 MB 失败记录保留为历史结果；当前验收以 v3 的峰值、回落、循环增长和交互指标为准。
