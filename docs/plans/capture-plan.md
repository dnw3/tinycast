# Capture 一期实施 Plan

2026-09-29 决定：按用户要求将统一 100 MB 改为 [Spec v3 分场景预算](capture-spec.md#内存和性能-gate)，
普通截图/长图与 OCR/录制分别为 300/512/600 MB，同时检查回落与循环增长。以下历史失败保留。
WebP 见 [决策文档](capture-webp-decision.md)：2026-09-29 用户已批准官方 libwebp 静态依赖例外；现有 Save 已接入，短生命周期 helper 的 20 轮原生资源与像素验收通过。

状态：2026-09-29，原生实现持续推进，一期未验收完成。当前实现、完整能力扩展与剩余项统一见
[交付状态](capture-delivery-status.md)，原一期证据见[验收记录](capture-acceptance.md)。

收尾核对：Spec、Plan 与交互方案已形成设计基线，核心流程已有实现；任务清单仍有未关闭的原生和性能验收。
本轮修复后 86 个 harness、普通/优化 Debug 与 Release 构建、Capture lint、Model 纯度和严格签名检查通过。
AC-15 已收口，日志与源码身份见[最终检查](capture-evidence/capture-final-checks-20260929.json)。
用户已要求继续验收。普通截图和录制均完成新的 20 轮，资源预算通过，入口 P95 分别为 456/467 ms。
长图预览 P95、外部设备和其余原生矩阵继续验收；未缩减已确认范围，也未将待验条目改为完成。

对应 [Spec](capture-spec.md) · [交互设计](capture-interaction.md) · [原型](capture-prototype/index.html)。

2026-09-24 扩展路线见[统一工作区方案](capture-unified-workspace.md)：先完成原位编辑与长图入口，再接图片增强、录制和视频编辑。以下仍为一期任务与证据，不代表新增能力已交付。

当前原生交互改版及验证进度见[统一工作区落地记录](capture-workspace-implementation.md)；本文的一期资源与兼容性闸门继续保留。

## 1. 交付原则

- 一期包含长截图，不能以普通截图子集替代交付。
- 先解决长图内存、编码和输入事件的真实可行性，再扩展工具栏；每个里程碑必须有可运行结果。
- 已获授权更新设计并开始本地原生实现；完成状态以证据为准，发布和上游 PR 单独处理。
- 现有 Translation 与其他未提交变更属于前序工作。记录开始快照，局部修改，不重置、不清理、不创建额外分支。

## 2. 依赖和关键路径

```mermaid
flowchart LR
    G0["G0 可行性与预算"] --> G1["G1 纯模型与存储"]
    G1 --> G2["G2 捕获与最小编辑"]
    G2 --> G3["G3 长截图完整链路"]
    G3 --> G4["G4 标注、输出、贴图"]
    G4 --> G5["G5 OCR 与翻译"]
    G5 --> G6["G6 历史、设置、集成"]
    G6 --> G7["G7 原生验收与性能收尾"]
```

G3 的最小画布、PNG 输出和暂停/完成必须工作；不等待全部标注工具完成后才发现长截图不可行。
估时在 G0 后以实测和首个纵切实现更新；不以源码行数直接换算交付日期。

## 3. G0：可行性与资源决策

目标：用最小原生 harness 排除会使全部设计返工的风险。产物放任务专用 evidence 目录，标注 Dev bundle 和工具链。

- [x] 记录 git 状态、系统/SDK、机器和屏幕配置，测 Tinycast 当前 idle/peak/RSS/footprint 基线；结果未达标见 G0。
- [x] 检查许可清单：逐项记录参考 Macshot 文件和处理方式；本轮没有移入其源码，见 [G0 记录](capture-g0.md#5-来源清单)。
- [ ] 用 SCScreenshotManager 验证区域、窗口、5K、鼠标和短暂菜单捕获；验证 palette 消失后不残影。
- [ ] 验证滚动控制条不抢页面滚轮、手动模式不依赖 AX、自动模式只影响目标窗口，以及重复热键完成。
- [ ] 制造确定的 1600 × 30000 图片和滚动帧，验证文件分块、视口预览和逐步增长时内存不线性常驻。
- [x] 对比 ImageIO/CGDataProvider 与系统 zlib 分行 PNG；选用后者，标准/高熵长图各 4800 万像素独立解码比对通过。
- [ ] 验证大图写 pasteboard 与 Finder/图像应用粘贴，记录是否触发整图解码、provider 生命周期与编辑器关闭后的数据可用性。
- [x] 48 MP 长图、三个贴图、OCR、PNG Save/Copy 组合 20 轮通过；主进程/helper/同时总和及精确五秒回落见 [报告](capture-evidence/combined-20-20260929.json)。
- [ ] 记录 G0 决策：捕获帧上限、tile 上限、PNG writer、clipboard 交付、是否需要媒体 worker。

通过条件：AC-14 的内存门槛有可重复证据；PNG/clipboard 原尺寸输出成功；无法匹配时有保留结果路径。
无可行路径时提交具体测量和最小范围/预算修订，不默默放宽标准，也不宣布长截图已落地。

候选的“系统 zlib 分行 PNG”只在 ImageIO 路径未达到预算后评估，不预先增加两套生产编码器。
增加 helper 如有必要，要额外验证 TCC 归属、签名嵌入、取消/退出、结果文件租约；移到别的进程不是预算豁免。

## 4. G1：纯模型、会话和存储

输入：G0 已选定资源方案。

- [x] `CaptureRequest`、`CaptureDocument`、`CaptureAnnotation` 及文档中的 `revision` 整数，使用纯 Sendable 值。
- [x] `CaptureGeometry`：屏幕/像素/文档/视图映射、负原点、1×/2×、裁剪取整；窗口阴影采用 SCK ignoreShadows，实屏边界仍待 G2。
- [x] `CaptureSessionState`：prepare/select/scroll/pause/edit/output；session ID + revision 隔离迟到事件。
- [x] `ScrollStitchPolicy`：稳定性、重叠、重复帧、倒向、固定区域、无进展、尺寸/资源上限。
- [x] `CaptureUndoHistory`：参数化操作、一次拖动一个动作、分组撤销；不复制图像。
- [x] `CaptureRepository`：临时 session、不可变 tile、manifest 原子发布、引用租约和过期回收。
- [x] 加入最小可独立编译 harness，并登记 `Scripts/run-tests.sh`；每个 harness 使用唯一临时目录。

验证：几何往返、整数边界、无穷/NaN、重复/迟到事件、取消与发布竞争、失效 manifest、磁盘写失败。
退出条件：没有 AppKit/SwiftUI/Cocoa 进入 Model，没有新的 singleton/actor，AC-02/04/05/07/11 的纯逻辑部分通过。

2026-09-29：上述模型与存储实现由 capture-session/raster/editor/workflow/transform harness 覆盖；85 个全量测试通过。
这里只关闭纯逻辑实现，G0 与原生验收仍独立保留。

## 5. G2：命令、捕获和最小画布

- [x] AppCore 延迟持有 CaptureCoordinator；新增 CommandID 和 SettingsTab ownership，不另建快捷键系统。
- [ ] `ScreenCaptureService` 采用现代 SCK；按需请求 Screen Recording；权限恢复必须用户重试。
- [ ] 非激活遮罩、拖动选区、窗口选择、全屏、屏幕切换；屏幕拔出/锁屏中止当前捕获。
- [x] 普通选区 Return / Command-C 直接复制；编辑是次动作，不为快速路径新增命令。
- [x] AppKit 画布 + SwiftUI 工具/输出条；缩放、裁剪、复制 PNG 已有独立解码及原生证据。
- [ ] 独立 editor 的 ActivationPolicy、focus return、未保存内容、新截图重入和关闭统一路由。
- [x] Theme/InterfaceMetrics 只新增确有需要的 Capture token；不修改旧 dark 值和两个禁改 scrolling 文件。

验证：首开/连开/取消、palette 与直接热键入口、权限拒绝、负坐标/Retina、明亮桌面下 Light/Dark。
交互闸门：普通选区 → 复制 → 返回原应用，不经过编辑器；未编辑普通图一次 Escape 关闭，新截图无需草稿确认。
退出条件：一个真实截图能以准确尺寸进入编辑器、复制并被外部应用解码；不将 UI 自动化的应用内按键当成 Carbon 热键证据。

## 6. G3：长截图纵切交付

- [ ] 选择区域和方向后还原 live 页面，仅保留控制条、捕获边框与预览。
- [ ] 串行稳定帧采样和 registration；将平台结果转为纯 `ScrollStitchPolicy` 输入。
- [ ] 纵向与横向、手动和显式自动；固定页头/侧栏、滚动条处理。
- [ ] 暂停、继续、完成、丢弃、保留已有、回到重选；状态机与交互稿 U03 一致。
- [ ] 目标移走/遮挡/应用切换、显示器变化、权限撤销使采样和自动事件及时停下。
- [ ] 保存条带后释放旧输入帧；增量预览、viewport tile 加载和有界 PNG 导出。
- [x] 长图初次打开按短轴适配，直接看清正文并沿长轴滚动；1600 × 30000 原生重开为 61% 适宽，整图概览为次动作。
- [ ] 达到长度/像素/磁盘资源上限时保留已提交内容，不截断后伪装完整页面。

固定样本至少覆盖：编号 1…500 的纵向文档、横向宽表、固定页头、固定侧栏、混合字号中英、相同句子重复出现、
反向滚动、相同帧、无纹理、动画块、间距突变、超大位移、字节行对齐和 RGB 布局。
纯 fixture 必须验证最终图像行列及来源区段，不仅验证“返回成功”。

真实 corpus：浏览器文档、PDF、原生长列表、横向表格；每个记录手动/自动、显示倍率和停止原因。
退出条件：AC-03/04/05 的测试与原生路径通过；真实长图能编辑、保存和复制，内存重测达到 G0 结论。

## 7. G4：标注、输出和贴图

- [ ] 实现选择、箭头、矩形、椭圆、文字、画笔、编号、实色/像素化遮盖；文字 IME 和独立 undo。
- [ ] 标注命中、拖动/缩放、裁剪后坐标及剪裁区外标注规则，所有动作可撤销。
- [ ] Copy/Save 固定 revision；取消、输出失败与发布竞争；JPEG/HEIC 大图能力按 G0 结论显式限制。
- [ ] Clipboard mutation handshake 和内部 marker；disabled/排除来源策略；只记录最终图片一次。
- [ ] 贴图：三个有界预览、拖动/缩放/透明度、复制/编辑/关闭、不同 Spaces/全屏应用场景。
- [ ] 保存失败保持编辑器；Copy 成功关闭策略；菜单与文字输入优先消费 Escape/快捷键。

退出条件：AC-06/07/08/12 通过，所有输出独立解码且图像像素与该 revision 对齐；20 次开启/关闭无持续增长。

## 8. G5：OCR 与现有 Translation 接通

- [x] 把共享识别与进程协议迁入 Platform/TextRecognition；移除旧公共名字及重复入口，保留 searchIndex 的既有行为。
- [x] project.yml 更新 helper target 与打包路径，再运行 xcodegen generate；禁止手改生成工程。
- [ ] searchIndex/captureText 两种用途策略；长图保留原像素分块；文字框映射和重叠去重。
- [ ] 结构化、受限结果与 truncated 状态；helper 超时/取消/崩溃后进程被回收，背景索引依原设置恢复。
- [ ] 同一文本面板承载 OCR 与翻译：选择、编辑、复制、重试；空结果/部分结果/超过翻译上限路径。
- [ ] Capture 文本会话失焦保留；切到原应用再返回，原文、译文和正在进行的任务都保留；显式关闭才释放。
- [ ] Translation 的新文本入口清空 target，禁止 OCR 来源 Insert/Replace；不改变原选区入口。
- [ ] Apple 缺语言包、AI route 缺失、真实结果、过期响应、显式截断和取消。

回归重点：剪贴板索引的启用/禁用、旧等待任务结束、Translation 旧选区回填策略、AI route 不共享聊天上下文。
退出条件：AC-09/10 通过；截图翻译与原生选区翻译都由各自证据支持，未配置的服务明确记未验证。

## 9. G6：历史、设置与完整接入

- [ ] 最终图历史、缩略图、搜索/日期分组、清理；平面与可编辑原稿的标识、重新打开。
- [ ] 草稿/可编辑原图留存明确选择；保留原稿开关默认关闭；缺侧车时平面恢复。
- [ ] Capture grouped Form、SettingsAnchor、SettingsSearchCatalog、命令别名与快捷键配置。
- [x] 备份覆盖登记与 exclusions，导入不启用原稿留存、不恢复采样/自动滚动状态。
- [ ] 从剪贴板图片 Actions 进入四条相同路径；无图/失效文件不关闭 palette 后静默失败。
- [ ] 退出/关闭功能时统一处理采样、helper、输出事务、未保存草稿及贴图。
- [x] 编写正式 `docs/features/capture.md`，此时才更新 architecture 的“已实现”表述。

退出条件：AC-01/11/12 通过；Dev 数据都在独立 bundle root；没有更改 Macshot 数据、安装或配置。

## 10. G7：收尾验收

| 类别 | 检查 |
| --- | --- |
| 定向 harness | capture geometry/state/stitch/annotation/repository/output；clipboard-text/search/pasteboard；translation |
| 完整检查 | `./Scripts/run-tests.sh`、`./Scripts/lint.sh`、Model import 检查、`git diff --check` |
| 构建 | Debug 零新增 warning；Release 验证并发/编码边界；记录工具链与 commit/diff 身份 |
| Native QA | Spec AC-01…AC-15 逐项，失败和未覆盖不能记通过 |
| UI | 明亮桌面 Light/Dark；Interface Size 全档；键盘、中文 IME、VoiceOver、焦点、窗口重开 |
| 性能 | G0 同一机器/素材/采样方法对照；短图/长图/贴图/OCR/编码/剪贴板/20 次循环 |
| 故障 | 拒绝/撤销权限、helper crash、磁盘失败、断屏、目标消失、重复热键、退出时正在保存 |
| 文档 | feature/architecture/testing/development/README 与实际实现一致；新增来源 NOTICE |

按 repo 的 definition of done 完成后，才在本 Plan 勾选相应实现项。
完整测试通过后不无理由重复跑；只在新增修改、失败或未解决问题需要时重跑相关项。
原生视觉录屏与截图需要可核对的前后对照；网页原型不替代 macOS rendering QA。

2026-09-29：最新入口和重新框选修复已完成上述代码检查，无新增构建 warning。
全量 86 个 harness 通过，测试阶段 394 秒，含编码器准备的总耗时 411 秒；
普通 Debug 与 Release 均在独立目录构建，未覆盖正在运行的签名 Dev。
这关闭 AC-15，不替代其余 AC 的真实系统、设备和交互验收。

## 11. 文件落点与所有权

| 文件/模块 | 改动职责 | 依赖 |
| --- | --- | --- |
| `Features/Capture/Model/` | 请求、状态、几何、拼接决策、文档与撤销 | Foundation/CoreGraphics |
| `Features/Capture/Service/` | SCK、配准、tile I/O、render/export、repository | Apple 平台 API |
| `Features/Capture/UI/` | coordinator、overlay、scroll controls、editor、pin、OCR/history | Theme / Platform |
| `Features/Capture/Settings/` | grouped Form、settings store | AppSettings / Settings shell |
| `Platform/TextRecognition/` | 共享 OCR worker/helper 与边界协议 | Vision 仅进 helper |
| `AppCore` | 持有、注入、跨 feature 闭包连接 | 不增加业务实现 |
| `CommandID` / `CommandCatalog` / `LauncherCoordinator` | 命令枚举、归属、分发 | CaptureCoordinator |
| `TranslationCoordinator` / `TranslationState` | 已识别文本入口、source、target 清空 | 现有翻译服务 |
| `ClipboardCoordinator` / `ClipboardManager` | 图片动作及单次结果接收 | 不承载 Capture 文档 |
| `Theme` / `InterfaceMetrics` | 仅新增 Capture 所需 token | 旧 dark 值不变 |
| `Settings*` / `SettingsBackupCoverage` | 搜索锚点、偏好及排除策略 | Capture settings |
| `project.yml` / generated xcodeproj | helper 源文件与构建边界 | xcodegen |

### Macshot 参考代码的处理

以下路径相对 Macshot 仓库；G0 建立来源清单后才决定具体复制范围。

| 参考入口 | 在 Tinycast 中的处理 | 首要验证 |
| --- | --- | --- |
| `macshot/Capture/ScrollFrameAnalyzer.swift` | 提取配准与判定思路，拆成平台分析器和纯 `ScrollStitchPolicy` | 固定区域、重复内容、失败置信度与像素 fixture |
| `macshot/Capture/ScrollCaptureController.swift` | 参考会话流程；捕获、调度、生命周期按 SCK / Swift 6 重写 | 输入焦点、取消、目标变化与有界帧队列 |
| `macshot/UI/Tools/AnnotationToolHandler.swift` | 参考工具分发接口，建立独立画布工具；不继承巨型 OverlayView | hit testing、拖动分组撤销、TextKit |
| `macshot/Model/Annotation.swift` | 重新定义纯值标注；AppKit 绘制和图片对象放 Service/UI | Model 纯度、坐标及输出 revision 一致性 |
| `macshot/Services/HistoryStorage.swift` | 参考历史交互，按 Tinycast 渠道路径和文档租约重建存储 | 原稿留存、崩溃恢复、清理与活动引用 |
| AppDelegate、快捷键、翻译、更新和上传模块 | 使用 Tinycast 对应能力或保持本期范围外 | 不引入重复状态所有者和服务配置 |

## 12. 可审阅的切分

1. G0 报告 + G1 纯模型/存储与定向 tests。
2. G2 最小原生捕获闭环。
3. G3 长截图（一期关键门槛）。
4. G4 标注/输出/贴图。
5. G5 共享 OCR 迁移与 Translation 接口。
6. G6/G7 集成、文档与完整验收。

以上是本地实施切分，不预创建 branch/commit/PR。若之后需要上游贡献，先按 CONTRIBUTING 的 approved issue 流程推进，
并处理第三方 GPL 代码与贡献协议的适用范围；本次不向外发送提案或消息。

## 13. 决策记录与本轮交付

| 决策 | 状态 | 依据/产物 |
| --- | --- | --- |
| 长截图纳入一期 | 已确认 | 用户 2026-09-23 指定 |
| 原生 Capture + 现有 Translation/Clipboard | 设计基线 | Spec §2/7/9 |
| 手动默认、显式自动，纵向/横向单轴 | 设计基线 | Spec §5；交互 U03 |
| 图像分块、撤销存参数 | 已实现并通过像素/撤销 harness；v3 下 48 MP/OCR/三贴图组合 20 轮资源通过 | [组合报告](capture-evidence/combined-20-20260929.json)；旧预算失败保留在 G0 |
| PNG / pasteboard 具体实现 | 流式 PNG、8 MB 编码限制已接通；编辑器复制与直接选区复制到 Preview、历史去重通过；超限保留原尺寸保存路径 | 普通图实测见 [验收记录](capture-acceptance.md)；跨应用大图交付完整矩阵仍待验 |
| 媒体 worker 是否必要 | WebP 已采用短生命周期 helper 并通过 20 轮；录制保持进程内实现，基础全屏录制 20 轮资源通过 | [WebP 决策与报告](capture-webp-decision.md#helper-原生-20-轮验收)、[录制报告](capture-evidence/video-native-20-report-20260929.json)；设备增强仍待验 |
| 原生功能实现 | 入口、长截图、编辑、OCR/翻译、历史均有实现；不可标为交付完成 | [当前验收](capture-acceptance.md) |

### 2026-09-23 v0.1 设计交付检查（历史记录）

| 检查 | 实际结果 |
| --- | --- |
| JavaScript 语法 | `node --check docs/plans/capture-prototype/app.js` 通过 |
| 文档与资源链接 | 新增文档/HTML 的本地目标文件均存在；新增文本无行尾空格；`git diff --check` 通过 |
| 入口与长截图模拟 | 搜索“长截图”并 Return 进入；横向 `2220 × 960` 在捕获、编辑器、复制历史与回开后保持一致 |
| 滚动控制 | 手动增量、暂停后不增长、继续、自动增长及演示上限停止；控制条 Space/Return 路径通过 |
| 异常恢复 | 拼接失败后保留已有内容；模拟屏幕权限授权后显式重试；模拟保存失败重试后标注仍保留 |
| 编辑与输出模拟 | 鼠标拖动绘制箭头；新增标注撤销/重做；复制关闭默认生效，关闭该设置后编辑器保留 |
| OCR/Translation 模拟 | 进入译文、无回填按钮；15,885 bytes 输入阻止整段翻译并显示提示 |
| 贴图与历史模拟 | 透明度 100% → 99%；平面回开没有原标注，可编辑样本保留原标注 |
| 外观与运行日志 | 当前浏览器视口下检查深浅编辑器及长截图；运行日志没有捕获到 warning/error |

走查修复了原型桌面被焦点滚动导致编辑器裁切、长截图控制条重绘丢焦点、横向结果尺寸颠倒和历史回开尺寸不一致。
可复现步骤见 [原型 README](capture-prototype/README.md)。

v0.1 设计交付时未改 Capture 生产代码、未运行原生截屏/OCR/翻译/性能或 Swift 构建测试；此记录不能作为实现验收。
浏览器原型的完整 Undo、像素裁剪、多窗口和 IME 等差距见交互设计 §12，不把模拟反馈记作系统行为已验证。


### 2026-09-23 v0.2 更新与第一批实现（历史记录）

四条评审结论已同步到 Spec、交互设计和原型：普通选区默认复制；普通未编辑图片关闭免确认；
长图按短边适配；OCR 与翻译同面板且截图来源失焦保留。取字原文修改会撤下旧译文，避免显示过期结果。

已新增 Capture 的尺寸/tile 模型、行读写、系统 zlib PNG writer 和 viewport 策略，纳入 XcodeGen 工程。
这是 G0 数据路径和 G1 存储基础，尚未连到 AppCore 或用户入口。引用租约、会话 revision、滚动增量 manifest
及 CaptureRepository 整体没有完成，不勾选 G1/G2 或一期完成。

- 定向 `capture-raster-test` 通过；源码、复现命令与数值见 [G0 记录](capture-g0.md)。
- 完整 suite 最终 78/78 通过；首次并发运行的 `clipboard-text-test` 出现计时超时，独立复现通过，完整重跑也通过，未修改该 harness 或 OCR 代码。
- `./Scripts/lint.sh` 通过、无新增 lint warning；Model 无 AppKit/SwiftUI/Cocoa import。
- 同一 1600 × 30000 样本，独立进程最大 RSS 从 ImageIO 的 213.07 MB 降至 17.60 MB。
- 高熵长图保存 PNG 时最大 RSS 9.16 MB；直接写入私有 pasteboard 时约 508 MB，仍须解决交付预检和降级保存。
- Debug 以本地签名 override 构建通过；默认签名身份在本机缺失，详细边界见 G0 §4。
- v0.2 浏览器走查：Return 直接复制、未编辑关闭不弹确认、长图关闭保留确认、默认适合宽度、同面板校正/翻译及修改原文后撤下过期译文通过。
  当前内嵌浏览器中 Command-C 未能触发，保留为原生键盘验收项，不计作通过。
- 原生捕获、拼接、预览、窗口焦点、实际接收应用粘贴和完整内存回落尚未验收。

后续按 G0 剩余现场验证 → G1 会话/租约 → G2 捕获闭环 → G3 长截图推进，保留一期完整范围。

### 2026-09-23 v0.3 原生实现

已接通 AppCore/命令/设置/剪贴板入口、SCK 与多屏选区、纵横滚动会话、条带配准和增量预览、
独立编辑器和标注、流式 PNG/有限 JPEG/HEIC 输出、贴图、历史和可编辑草稿、共享 OCR helper、
截图文本与现有 Translation。未引入 Macshot 源码、额外依赖、分支或发布变更。

本轮完整 82/82 harness 通过；原生图片导入、各标注工具基础操作、裁剪及键盘撤销/重做、遮盖后 OCR、
真实 AI 译文、PNG 保存、历史/草稿重启恢复与贴图返回编辑已有证据。文字输入颜色和重编辑重影已修正并复验。
勾选的任务仅代表该行对应的代码和检查完成，不代表整个里程碑或一期验收完成。

G0/ G7 仍未关闭：绝对 RSS 门槛已失败，100 MB 标准未改。普通 Copy 已移除使小图始终失败的 RSS 拒绝，
保留 8 MB 编码上限；普通图外部应用接收、历史单次记录已通过。用户已允许两项权限，修复 Dev 旧签名记录后
真实 SCK 选区/取消、Arc 四种长图组合已运行；完整滚动 corpus、外接屏、IME/样式/VoiceOver 和 20 次循环尚未完成。
TextKit 组词与提交键、Unicode、多行、私有剪贴板复制和撤销测试已通过；JPEG/HEIC 像素及超限原文件保护通过。
原生预览发现的分块接缝已通过回归测试修复，等待原生复验。文件租约与崩溃遗留 session 回收已实现并通过 fixture，
仍需退出路径复验。实际锁屏暴露选区资源未释放，新增了锁屏/休眠中断监听及通知路由和生命周期 harness；
该修复尚待原生锁屏验证。逐项证据、失败与未覆盖边界见 [验收记录](capture-acceptance.md)。

### 2026-09-24 原生验收续测

普通区域 Return 直接复制、Preview 独立解码/再导出及单条 Clipboard 接收已通过。
用户完成授权后，当前 checkout 的 SCK 选区实际运行。长截图先后定位到系统指针和 Dock 全屏表面的
遮挡误判；现有修复保留真实窗口遮挡保护，并让长截图 SCK filter 与可见性检查共用应用排除名单。
Arc 样例的纵/横向、手动/自动四种组合均完成真实多帧拼接和 PNG 输出；完整 corpus 仍不关闭 G3。
临时签名重编译会使 TCC requirement 失效。
用户已批准本地稳定签名凭据，当前 Dev 和 OCR helper 已用固定证书构建并通过严格签名校验。
重新登记准确 Dev 后，两个不同 CDHash 的构建重启均通过录屏及辅助功能运行时检查，中间无需重新授权。
前台交接后导出 1500 × 3276 长图，002–024 连续，行分隔线间距全部为 142 像素，历史匹配恰好一条。
自动事件改走系统 session event 路由后，纵向输出 1500 × 3880，063–089 连续，行距同为 142 像素。
横向自动输出 3920 × 760，手动输出 3420 × 760；完整列号逐行连续，列分隔线间距全部为 446 像素。
四个输出各匹配一条历史。横图默认按高度适配，保存后关闭不再询问。
启动暂停的一处原因是工具指针浮窗与选区相交，保留真实遮挡保护；另一处是屏上清单漏掉隐藏的自身应用，
已改为完整清单建立排除集合、只使用屏上目标窗口，并完成原生输出复验。遗留系统弹窗已由用户收起。
构建脚本在覆盖签名 bundle 前停止准确路径的旧进程；build-only 会拒绝覆盖运行中的 app。
长期 fork 的应用身份、Release 构建与安装替换仍处于方案讨论，尚未实施。
G0/G7 的 100 MB RSS、完整原生矩阵和 20 次循环仍未通过，逐项状态以验收记录为准。


### 2026-09-28 新工作区续测

新入口四种长图均已得到多帧产物，并通过独立 ImageIO / Vision 连续行列检查；
新增原尺寸 PNG 系统保存和 50% AVIF 保存证据，修复了保存 sheet 的键盘优先级。
选择增强、高级标注、QR 与导出模型已进入当前 Debug；本构建 82/82 harnesses、lint、Model 纯度通过。
具体尺寸与证据见[工作区落地记录](capture-workspace-implementation.md#2026-09-28-续作记录)与
[原生产物记录](capture-evidence/workspace-native-20260928.json)。
G0/G7 的绝对 RSS、混合倍率/5K、完整原生矩阵与循环性能仍未通过；B/C/D 未实现能力不计完成。


### 2026-09-29 图片与录制收尾

完整功能与原生逐项状态统一见[交付状态](capture-delivery-status.md)，这里不以实现按钮替代验收。
新增长图短轴适配、20 种 PNG 行过滤/通道回归和 90 行原生 OCR 接缝复验；
新录制管线的窗口最小化、隐藏时拒绝恢复、原窗口恢复、目标关闭与全屏输出均获得实际 MP4。
全量 85 个 harness 在四并发下通过（172 秒），Debug、Capture lint、Model import 与 diff 检查通过。
普通截图 20 次循环已测，峰值 268.5 MB、关闭五秒后 196.2 MB，原 100 MB 绝对标准失败；
该次测量使用旧门槛；2026-09-29 已按用户要求采用文首 v3 分场景预算。G0/G7 的完整复验、外部硬件、设备授权和故障矩阵仍未关闭。


统一交互方案中“工具库加入常用栏”已补齐，原位与独立编辑器共享配置，保留默认图标数量。
尺子/QR 加入、重启持久化、原位复用和恢复默认均通过原生验证；本增量全量 85/85 通过（173 秒）。
追加截取向右窗口与向下整屏均已逐像素核对，可编辑草稿重开、单步撤销/重做及取消恢复通过。
