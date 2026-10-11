# Capture 完整体验实施计划

依据：[Spec](capture-product-spec.md)。日期：2026-10-10。
当前工作区保留此前效率与工具栏对齐实现；本计划不将它们重复计算为新交付。

## 执行顺序

| 阶段 | 交付 | 依赖 | 状态 |
| --- | --- | --- | --- |
| S1 | 全部工具、统一常驻勾选、滚动/录屏直接入口、偏好保留 | 现有工具栏 | 实施中 |
| S2 | 排序、实时预览、窄屏溢出、目录搜索 | S1 | 实施完成，边缘矩阵/辅助功能待验收 |
| S2.1 | 原分辨率冻结背景、首帧布局、光标状态、像素颜色提示 | S2；优先修复基础手感 | 用户反馈启动与光标目前正常；连续视频、多屏与量化门槛待验收 |
| S3a | 箭头样式、形状填充与圆角 | 文档/渲染一致性测试 | 已实现、签名安装并完成本阶段验收 |
| S3b | 富文本与原生编辑 | 样式片段格式与旧文档测试 | 已实现、签名安装并完成本阶段验收 |
| S3c | 统一遮挡及 Text Only | OCR 框/隐私像素验证 | 已实现、签名安装并完成本阶段验收 |
| S4 | 长截图真实矩阵与连续工作流修复 | S1；设备及真实页面 | 交互/焦点已修正，真实拼接矩阵待验收 |
| S5 | 编号/平滑/文字高亮/美化预设 | S3 | 已实现、签名安装并完成本阶段验收 |
| S6 | 录屏性能及 120fps 决策 | 实机能力与资源结果 | 设备初查完成，持续录制/资源待验收 |

## S1 工作清单

- [x] 扩展工具目录覆盖捕获、识别、输出，不新增重复执行路径。
- [x] All Tools 始终可发现，执行与常驻勾选分开。
- [x] 两组常驻勾选、合理默认、旧配置保留及隐藏偏好重启验证。
- [x] 选区后 Scroll Capture 直接手动采样，方向/调整在菜单中，保留返回截图语义。
- [x] 上下文可用性、忙碌互斥及原有快捷键不变。
- [x] 回归测试、Debug、lint、纯度和文档；记录原生视觉/交互边界。

## 后续阶段拆解与验收门槛

S2 先定义有序配置和有限溢出策略，再接拖动/上下移动；无空间时确保关闭/取消可达。
S3a 每种箭头/填充用固定几何与独立解码验证；S3b 先做样式格式及 Unicode 边界测试，
再接编辑器和渲染；S3c 先合并 UI 再补 Text Only，不删除旧文档类型。
S4 逐例保存匿名资源和结果；失败先复现再修复，真实服务无凭证不标完成。
S5 拆为编号、画笔、高亮、美化四个可独立验收任务。
S6 产出帧率能力报告，达预算才实现选项，否则记录决定及原因。

## 验证记录

2026-10-10：S1 代码及自动检查完成，完整原生交互验收继续记录；当时 S2–S6 未完成；当前 S2 进展见本文末。

- 完整 `./Scripts/run-tests.sh`：104/104 通过（153 秒）；新增配置测试覆盖旧标注配置、默认操作、全隐藏后重新读取、损坏/超限配置和目录完整性。
- Debug 构建成功，无新增 Swift 警告；保留既有 AppIntents metadata 提示。
- lint 通过，现有 66 条警告无新增；Model AppKit/SwiftUI/Cocoa 无匹配；`git diff --check` 通过。
- [匿名组件预览](capture-evidence/product-toolbar-native-20261010.png) 已检查，新增卷轴入口保持相同按钮尺寸与中心线。该图为共享原生组件的离屏组合，背景及翻译符号是示意，不代替完整应用交互验收。
- XcodeGen 已更新项目。排序、窄屏溢出、实时自定义预览和搜索留在 S2；当前仍按固定目录顺序显示。

- 首次原生交互检查：在公开页面区域完成普通选区，右侧卷轴按钮可点击并进入滚动准备；Vertical/Horizontal 与已启用的 Start Scrolling 可见，未重新框选。未启动实际滚动，随后关闭且未复制、保存或上传。
- 原生检查发现平铺目录过长，已改为 Annotations / Image and Recognition / Capture and Output 三组子菜单；自定义按两条工具栏分组。最终版已验证根目录为四行分组入口，不再平铺全部工具。

- 最终签名 Release 构建成功，安装至 `/Applications/Tinycast.app`，完整签名验证通过并启动（PID 84050）。安装记录：`build/install-backups/efficiency-install-8e4e5a1048.json`，旧版已备份。
- 原生菜单根目录及滚动准备流程已检查；嵌套菜单的实际勾选和键盘/VoiceOver 访问，本轮 UI 自动化没有完成验证，保持待验收。偏好模型的隐藏/重开行为已通过自动测试。
- 所有检查选区均已关闭，没有复制、保存或上传测试图片；临时公开页面已关闭。最终仅调整菜单分组和文案，既有 harness 不涉及这两处 UI 文件，未无理由重跑完整测试。

## S2 工作清单（2026-10-11）

- [x] 有序配置保存在既有偏好键；旧 Set 和不带顺序的配置读取保留选择。
- [x] 两组顺序独立，上移/下移可操作，选择固定首位；Reset 同时重置顺序和可见性。
- [x] 自定义面板有即时顺序预览、中文/英文/快捷键搜索与常驻勾选。
- [x] 桌面底栏不换行，超出空间仍可从 All Tools 执行；右栏预留关闭/展开/溢出空间。
- [x] 编辑器按自身可用宽度限制常驻标注数；显示配置变更会重新计算桌面工具栏位置。
- [x] 符号改回系统字体比例，箭头、展开和关闭采用 14pt 视觉尺寸，按钮仍为 30pt（随界面尺寸缩放）。
- [x] 完整回归、Debug、签名 Release、lint 及纯度检查。
- [x] 原生面板完整列表、中文搜索、勾选、即时预览、上下移动和 Reset。
- [ ] 复杂边缘矩阵、真实目录菜单执行及 VoiceOver 人工验收。

S2 的上移/下移按完整分组顺序工作，隐藏项保留位置；预览顺序对应实际方向，操作栏预览横向展示并注明 top to bottom。
三档原生按钮测试已扩展箭头和叉号，验证 63 个按钮/菜单布局组合。复杂桌面矩阵与 VoiceOver 人工验收仍需逐项记录。

### S2 自动验证与安装记录

- 完整 harness 104/104 通过，151 秒；按钮/菜单布局覆盖 63 个组合（含 Arrow 与 Close）。
- Debug 与签名 Release 通过，无新增 Swift 警告；lint 无新增警告，Model 纯度和 diff whitespace 检查通过。
- [符号比例原生组件预览](capture-evidence/product-toolbar-optical-20261011.png) 使用真实共享组件离屏渲染；该图不是完整应用验收。
- 原生小选区已检查 Arrow、Expand 与 Close 的视觉尺寸，默认底栏保持一排，关闭可见。
- S2 签名版本的旧版备份与签名/启动验证通过；自定义窗口尺寸修正的最终版本继续验收。
- Capture 设置与 All Tools 打开同一个自定义面板。⌘, 保留系统设置语义，不占用已有快捷键。
- 原生菜单坐标点击与键盘导航的自动化结果不足以确认菜单项执行，未将其记为通过。

### 原生面板验收发现与修正

- 从 Capture 设置成功打开独立自定义面板。中文“箭头”返回 Arrow/Curved Arrow；切换 Arrow 勾选后，预览和真实底栏同步更新，恢复勾选后恢复。
- Done 返回原选区，选区和默认工具保留；随后无编辑关闭，未复制、保存或上传。
- 实测发现 NSHostingController 自动尺寸使 List 高度被压缩：改为固定窗口内容尺寸，关闭自动 sizingOptions；列表行显式保留可访问子控件。
- ⌘, 会由应用菜单打开 Settings，已撤回自定义快捷键；不改变用户原有设置快捷键。

- 窗口尺寸修正后，原生完整列表可见；Arrow 下移会把预览变为 Select/Rectangle/Arrow/Text/Cover，Reset 恢复默认。Capture and Output 分组以“滚动”能找到 Scroll Capture，原勾选保持。
- 已恢复测试前默认可见工具与顺序，关闭测试选区、面板、设置和临时页面；没有复制、保存或上传。
- 最后一处视觉调整仅缩小自定义面板的排序箭头并采用同样的方形点击区域；完整 harness 的模型与服务未再修改，Debug/Release/lint 另行重检。
- S3–S6 尚未交付；S2 四边四角/明暗桌面完整矩阵、目录实际菜单项点击与 VoiceOver 人工验收保持未完成。

### 最终本机交付（2026-10-11 00:16）

- 最终 Debug / 签名 Release 构建通过；lint 通过，仍为既有 66 条警告，无新增 Swift 警告。
- 已安装并启动 `/Applications/Tinycast.app`（PID 98234），签名完整验证通过；记录 `build/install-backups/efficiency-install-4e457b0bc3.json`，旧版已备份。
- 最终原生窗口检查：完整列表可见，排序箭头缩小且使用统一点击区域；下移与上移均能改变预览顺序，测试后已恢复原顺序并关闭窗口。
- 上述是 S2 工具栏交付；S3–S6 与前述人工验收边界没有因安装而变为完成。

## S2.1 工作清单（2026-10-11）

- [x] 定位 900px 预览全屏放大的模糊来源；保留捕获原图，单屏/多屏同路径修复。
- [x] 呈现前布局与绘制；首次呈现同步更新指针，跟踪移动和进入事件。
- [x] 工具栏/选区外箭头、选区内工具光标、缩放手柄、退出恢复箭头。
- [x] 选区前像素放大镜、HEX 与原像素坐标，边缘避让，拖选期间跟随端点、完成后隐藏；不变更剪贴板。
- [x] 像素映射测试和完整回归 105/105。
- [x] 最终 Debug 与 lint（66 条既有警告，无新增 Swift 警告）。
- [x] 签名安装与原生选区、工具栏避让、关闭复验；热键/光标/连续帧验收见下一项。
- [ ] 热键首帧连续录屏、真实指针状态与多屏/不同缩放显示器人工验收。

优先完成基础手感再进入 S3；飞书的按键与独立截图浮层未被本轮自动化正常读取，
不据此声称已逐项复刻或已经优于飞书。原有 S3–S6 不因优先级调整而标完成。

### 用户视频对照

已在本机解码用户提供的约 14.27 秒视频，并逐秒检查选区前/拖选中/完成后的帧。
据此把像素放大镜从“开始拖选隐藏”修正为“完成选区才隐藏”；观察到飞书单排工具栏与取消/完成区分。
这份视频从截图状态开始，未覆盖热键触发前后，不作为启动无抖动的证据；没有上传用户视频。

### S2.1 自动与组件验证

- 完整 harness 105/105 通过（150 秒），新增测试覆盖 Retina 映射、Y 轴方向、屏幕边缘、无效坐标与相邻单像素条纹的精确 sRGB 色值。
- 新测试首次运行存在 CGFloat.nan 类型歧义，已修正；以上为修正后的完整重跑结果。
- 离屏真实原生放大镜组件：三档界面尺寸 × 四角均在屏幕内；采用紧凑两行标签和固定像素中心，避免色值变化引起卡片宽度跳动。
- [原生组件预览](capture-evidence/selection-loupe-native-20261011.png) 使用合成单像素条纹背景；不代表全应用启动/光标/多屏验收。
- 鼠标移动只重绘新旧放大镜覆盖区域；不会为每个 mouseMoved 重新绘制整个桌面。
- 对照视频只用于交互取舍，保留 Tinycast 自定义与简洁默认布局，不复制飞书长工具栏或配色。

### 原生复验发现的窄选区避让

已安装首轮 S2.1 签名版本并检查：文字背景清晰、初始像素辅助可见，完成选区后收起并显示工具栏，关闭返回应用。
同时发现窄选区的底栏外伸会挤占右栏原位置；原布局只避免两条工具栏相交，可能把右栏放进选区。
已改为侧向候选同时避让底栏外沿，并优先不覆盖选区；补充右侧和左侧可用空间的回归用例。
这是本机复验后的补充修正，需重新构建安装；首轮安装记录 `efficiency-install-ccd04eaf5b.json`。

### S2.1 最终交付（2026-10-11 01:26）

- 窄选区避让补充后的完整 harness 105/105 通过（152 秒）；Debug 和签名 Release 构建成功，无新增 Swift 警告，保留既有 AppIntents metadata 提示。
- lint 通过，66 条既有警告无新增；Model 纯度及 `git diff --check` 通过。
- 最终安装 `/Applications/Tinycast.app`（PID 24804），完整签名验证及启动通过；旧版已备份，记录 `build/install-backups/efficiency-install-16caf151a6.json`。
- 最终原生复验：初始控件旁的关闭可达；600×320 像素选区完成后放大镜收起，侧栏已在选区外，底栏保持单排，内容清晰；关闭返回应用。
- 测试选区和临时公开页面均已关闭，没有复制、保存或上传测试图，也没有更改工具栏偏好。
- 自动化应用内按键没有正常触发系统全局热键，鼠标事件也不足以证明实际系统光标形状；初始设置与切换逻辑已修正，但不声称 ⌃1 的首帧无抖动或完整光标序列已经通过人工验收。
- 本轮完成基础体验与窄选区遮挡修复；S3–S6 和既有待验收矩阵保留，不标记总体计划全部完成。


## S2.1 新视频回归（2026-10-11 01:42）

用户提供 `飞书20261011-014215.qt`：启动闪动仍存在，选区前 Close 独立悬浮，工具栏观感不协调。
撤回“基础手感已完成”的结论。逐帧检查新视频后，优先修复遮罩窗口仍使用默认动画的问题：
显式设置 `animationBehavior = .none`；保留原分辨率背景和展示前布局。
选区前、窗口目标选择、滚动准备和录屏准备，将 Close/Cancel 并入底部同一表面；
普通截图完成选区后才显示输出侧栏，宽度改为单个 30pt 控件加两侧共享 padding，
不再用 60pt 容器撑宽。关闭/取消共用同一组件，忙碌时仍可取消。
自动化与原生布局检查通过后更新本机；真实 Control+1 首帧无闪动仍需物理热键复验，
静态截图和代码中禁用动画不能单独证明该体验已通过。

验证记录（01:51 本机更新）：105/105 harness 通过（145s），Debug/Release 编译成功，
无新增 Swift 编译警告；lint 成功，66 条既有告警，无新增；Model 无 UI framework import。
已验签安装 `/Applications/Tinycast.app`，PID 33610，旧版已备份，
凭据 `build/install-backups/efficiency-install-620f1c8b3d.json`。
安装后原生检查期间检测到用户正在输入，停止自动操作，没有覆盖当前输入；
新版完整工具栏原生视觉与物理 Control+1 连续启动验收保留未通过状态。


### S2.1 接管路径进一步审查

详见 [截图启动接管分析](capture-startup-analysis.md)，对照本地 MacShot `39bcead`。
禁用窗口动画只关闭了一个风险；S2.1 仍修复中。按该分析先拆开底图显示与瓦片持久化、
分离固定图层与交互层、复用窗口，再验证显示色彩/阴影和最小扰动遮罩。
本轮为源码分析与计划补充，未变更 Swift 或重装应用，没有新增运行时已通过结论。


## S2.1 接管实施清单（整合 2026-10-11 分析）

本节是接管工作的当前清单；上文时间线保留为历史证据，不代表已通过本轮验收。

- [x] Spec 统一无感目标、捕获/显示/源准备/生命周期与连续首帧验收标准。
- [x] 固定 CALayer 底图与交互层分离，显式关闭窗口及图层隐式动画。
- [x] 待选原亮度，拖选/完成选区外遮罩；非目标屏无额外压暗。
- [x] 截图呈现使用 local intent、保留阴影和目标屏色彩空间；瓦片/导出仍 sRGB。
- [x] 按显示器复用空窗口，关闭释放内容和图片引用，淘汰断开的显示器。
- [x] 普通/跨屏源写入移至呈现之后，任务由 coordinator 独立持有。
- [x] 源未就绪时保留最后区域/窗口/跨屏选择，切 scope 清理，取消与 workspace 身份校验。
- [x] 依赖源的 editor/识别/输出延后到文件完整；失败关闭并报告，租约覆盖后台写入。
- [x] 保留自身窗口排除 filter；不直接迁入 rect API、旧系统 fallback 或近透明置顶预热。
- [x] 新增原生底图、内嵌画布像素与源准备状态测试；完整 108/108、Debug/Release、lint 和 Model 纯度通过。
- [x] 本机更新后原生拖选、关闭/重开、工具栏与光标交互通过；用户确认目前感觉正常，见下文范围。
- [ ] 物理快捷键连续视频、多屏/色彩/阴影、光标偏好、内存与释放专项通过。

明确取舍：本轮复用 NSPanel，工具栏宿主按会话创建。先测首帧，再决定是否继续复用宿主；
不以保留旧 workspace 的方法换取“预热”。底图安装无需整屏 CPU 重绘，普通 mouseMoved 只更新交互脏区域。


## 持续交付目标（2026-10-11）

用户明确目标：完成本 Spec/Plan，稳定签名安装本机，并通过验收。
总体目标保持进行中；S3–S6 不因 S2.1 安装而自动完成。
原生验收发现分层底图后桌面内嵌画布未正确显示，独立编辑器源图正常。
先隔离画布到自己的 backing layer，并用真实 CaptureCanvas 的裁切像素集成测试覆盖。
测试样本第一次使用非 UUID 栅格名被渲染器拒绝，修正样本后通过；该失败不作为产品源图损坏证据。
修正后的签名 Release 与完整回归进行中，原生复验通过后才关闭此缺陷。


### 接管修正版本机复验（02:21）

已签名安装 `/Applications/Tinycast.app`，PID 53524，记录
`build/install-backups/efficiency-install-27aa0f46a3.json`，保留前版备份。
真实桌面 600×320 选区内源文字可见，箭头绘制可见，Undo 恢复，Close 返回应用。
测试标注已撤销，没有复制、保存或上传；内嵌画布独立 backing layer 修正已在本机验证。
Debug 与 Release 构建通过，只有既有 AppIntents metadata 提示；lint 66 条既有警告无新增。
完整 108/108 回归通过（158 秒）；物理热键首帧连续视频与完整光标/多屏/资源矩阵仍未通过。

## S3a 箭头与形状实施（2026-10-11）

- [x] 可持久化 single/double/thick/open 箭头和 reverse；旧 nil 对应开放箭头。
- [x] outline/fill/both 形状模式、矩形 0/12/32px 圆角；半径受边长约束。
- [x] 编辑器属性与桌面 Style 菜单接线；不增加底栏常驻按钮。
- [x] 曲线控制点可拖动，保存独立旋转中心；移动/缩放/反射保持控制点。
- [x] 最终 PNG 独立解码、旧文档、撤销、归档与镜像回归。
- [x] 完整 harness、最终 Debug/Release、lint、匿名原生视觉证据。
- [x] 签名安装后的桌面 Style、独立编辑器与曲线控制点交互验收。

早期 Debug 曾因字段插入错误未编译，修正后编译成功；未将首次失败视为通过。

### S3a 原生复验（02:32 本机更新）

签名安装记录 `build/install-backups/efficiency-install-1cdfa3f5ca.json`，PID 65292。
匿名本机页面选区中用 Q 创建曲线、V 切选择并拖动控制点，弧度按拖动改变。
展开编辑器，Single 改为 Double，Reverse 勾选生效；矩形改为 Outline and Fill、Round，
属性值和画布同时更新。全部测试编辑已通过 Undo 撤销到不可撤销状态，关闭且未保存/上传。

- [双向曲线与属性区原生证据](capture-evidence/arrow-styles-native-20261011.png)
- [圆角填充与属性区原生证据](capture-evidence/shape-styles-native-20261011.png)

图片仅含匿名页面内容和真实 Capture 编辑器；源图中的指针提示来自桌面输入辅助层，
未对截图作修图。桌面 Style 根菜单确认包含 Arrow/Reverse；自动化未可靠操作它的子菜单，
因此此交互门槛仍待验收。原生曲线拖动、编辑器样式和撤销通过不代替该项。
完整回归首次 108 项通过，新样式测试的一条采样断言落在抗锯齿边缘失败；
采样移至内部后正在完整重跑，不将第一次完整回归标为通过。

### 回归发现的录屏取消竞态（S6 提前修复）

S3a 第二次完整回归的样式专项通过，原有 capture-video-test 在编码取消路径 SIGSEGV。
崩溃栈位于 AVAssetReaderOutput.Provider.next / copyNextSampleBuffer。
本机 SDK 的 AVAssetReader.h 明确禁止 cancelReading 与 copyNextSampleBuffer 并发；
旧取消处理器跨线程调用 reader.cancelReading，而两个 async let 样本任务仍可能运行。
[Apple cancelReading 文档](https://developer.apple.com/documentation/avfoundation/avassetreader/cancelreading())。

修正为取消处理器仅停止 writer，两个样本任务在下一次读取前检查取消；
async let 移入 do 的结构化作用域，退出并回收两个任务后才取消 reader。
未换用废弃读取 API，也未通过跳过测试掩盖问题。原视频测试补充 12 次编码中途取消，
每次要求 5 秒内结束且不留下输出文件，专项通过，包含此修复的完整 109 项回归已通过。
此修复不替代 S6 的录屏音轨/设备/120fps/资源完整验收。

## S3b 接续实施约束

采用可 Codable 的基础文字样式与有序 UTF-16 局部样式片段，标注的 text 仍是唯一文本内容；
不保存 NSAttributedString 的归档或未校验的 AppKit 对象。缺少新字段的旧文本沿用既有 font/fontSize/color。
样式片段验证长度、重叠、字符边界和数量上限；编辑和导出共享同一 CoreText 样式解释。

编辑期间的样式操作必须作用于 TextKit 当前选区或后续输入，不能先 finishEditing 破坏局部选区。
提交后再进入文档撤销历史；原生输入法标记文本期间不强制结束组合。
粗体/斜体/下划线/删除线、段落对齐、文字背景/描边均验证原生重新编辑和最终 PNG；
框宽/高调整影响换行，不能把文字当位图缩放冒充文本框调整。

实施顺序与独立门槛：

- [x] 定义基础样式、UTF-16 runs 与有限范围校验；拒绝越界、重叠和拆分 emoji 的片段。
- [x] CoreText 构建字体 traits、段落对齐和描边；按实际行/run 几何绘制背景与删除线。
- [x] NSTextView 导入/导出同一模型，局部选区修改保留其它 runs；粘贴只接受支持的样式。
- [x] 样式回调作用于活动 TextKit 选区/typing attributes，组合输入时保持 marked text。
- [x] 提交、重新编辑、缩放、镜像、归档与 Undo/Redo 保持样式；文本框调整重新换行。
- [x] 中文、emoji、混合字体、多行、局部样式的原生证据与 PNG 独立解码回归。

### S3a 最终安装与补充验收（02:50）

已安装包含反向状态隔离、录屏取消竞态修复的签名 Release，PID 86583；
记录 `build/install-backups/efficiency-install-6b7812f114.json`，签名要求与旧版一致且备份保留。
桌面 Style 根菜单打开后，使用 Down/Right 进入 Arrow 子菜单，Single 改为 Double，
画布立即显示双向箭头；此前子菜单自动化未验证项已补验。两步 Undo 恢复无标注，
Close 返回空搜索框，无保存、复制或上传。

最终 PNG 独立解码与预览逐通道比较允许最多 2/255 的抗锯齿舍入误差；
严格相等首次在曲线边缘发现三个色值差 1/255，几何、填充、方向断言保持独立严格检查。
最终样式专项通过，Debug/Release 通过；lint 通过（66 条既有警告）。
补跑最终完整回归时漏设 Node PATH，mcp-stdio/mcp-oauth/ext 三个 Node fixture 启动失败，
此轮不记通过；补齐运行环境后最终完整 109/109 项通过（155 秒）。
最终日志 `/private/tmp/tinycast-s3a-final-suite-node.log`；本阶段机械检查及原生交互验收完成。
整体 S3b–S6 与物理热键/多屏/资源门槛仍未完成。

## S3b 实施与专项验证（2026-10-11）

新增 Codable 基础样式与 UTF-16 runs，最多 512 个有序非重叠片段；只能在完整字符边界分割，
拒绝 NaN/无穷字号、越界及拆分组合 emoji。旧 nil 文本格式沿用原有渲染，编辑后存新格式。
粗体/斜体/下划线/删除线、左右居中对齐、背景和填充加描边均进入共享文档渲染路径。
桌面 Style 与编辑器 Text Style 提供相同操作；文本框调整只改变宽高及换行，不缩放字体。

原生 TextKit 专项已验证局部样式互不覆盖、Undo/Redo、两种缩放重新编辑、段落边界、
typing attributes、组合输入期间保持 marked text，以及提交后给组合文字应用排队样式。
RTF 通过私有粘贴板测试，不读写全局剪贴板；限定 RTF/纯文本，移除链接及不支持的属性。
增加缩放时粘贴保持文档字号的验证，最终回归进行中。

PNG 与整图预览的描边字体曾在条带边缘相差 3/255，增加上下各一行采样后通过原 2/255 精度。
垂直镜像曾因 CoreText 重做字形像素对齐导致最大 73/255 差异；改为原向 512px 小块绘制再镜像，
水平/垂直镜像专项通过。文档重开、归档、换行和每种样式的最终 PNG 已独立解码验证。

首次完整回归的旧 capture-editor-test 缺少新增依赖；修正编译源列表。
该轮又受运行期间编辑 runner 影响，已停止其进程树并作废，必须用稳定脚本重新完整验证。
签名版原生交互及匿名视觉证据未完成前，不关闭 S3b。

### S3b 最终安装与原生复验（03:20）

完整 111/111 项通过（183 秒），日志 `/private/tmp/tinycast-text-final-suite.log`。
最终 Debug 和签名 Release 均通过，无新增构建警告；lint 通过（66 条既有警告），
Model import purity 与 diff whitespace 检查通过。
签名安装记录 `build/install-backups/efficiency-install-a5203f3ba7.json`，PID 21762，前版已备份。

桌面选区新建 `Hello 中文 👩🏽‍💻` 与第二行，分别局部加粗、斜体、下划线；
提交后展开编辑器，双击重新编辑，AX 明确读出对应局部样式。
Text Style → Text Background → Yellow 只为 Hello 增加背景，提交后背景保留。
拖窄文本框后中文与第二行重新换行，字号字段仍为 24；再次双击，原始文字及局部样式保留。
原生 TextKit harness 另验证 System/Serif 混合字体、缩放重新编辑、RTF 字号和输入法组合。

- [提交后富文本原生证据](capture-evidence/rich-text-native-20261011.png)
- [文本框变窄及字号不变的证据](capture-evidence/rich-text-resize-native-20261011.png)

证据仅为匿名页面与 Capture 窗口；指针提示和录屏状态来自桌面辅助层，未修图。
全部验收编辑已撤销到 Undo 不可用，关闭窗口及临时网页，无复制、保存或上传。
S3b 本阶段验收完成；当时 S3c–S6、物理热键首帧/完整光标、多屏和资源门槛仍保留未完成。

## S3c 统一遮挡及 Text Only（2026-10-11 03:32）

- [x] 工具栏、All Tools 和自定义目录合成单项 Censor，菜单含 Solid/Pixelate/Blur/Erase/Text Only。
- [x] 旧配置可见性取并集、顺序取首个位置，不重复显示；旧工具编码与 B/M/F/E 保持。
- [x] Text Only 运行当前合成图 OCR，复用勾选、逐框审阅、批量应用与单次撤销；截断/空结果提示保持。
- [x] 实色/擦除在邻域采样前应用，最终再覆盖；像素化和模糊明确为视觉效果。
- [x] 两种隐藏原图值 × Solid/Erase × Blur/Pixelate/Magnifier，叠加锐化后最终 PNG 独立解码完全一致。
- [x] 真实 Vision OCR 验证 Text Only 候选应用后文字不可识别；取色、OCR、翻译与上传共用合成输出。
- [x] 完整 111/111 回归（183 秒）、Debug、签名 Release、lint（66 条既有警告）、Model 纯度和 diff 检查。
- [x] 签名更新至 `/Applications/Tinycast.app`，启动 PID 27676；安装记录 `build/install-backups/efficiency-install-c252fc9ec0.json`。
- [x] 原生匿名页面 Text Only 找到 4 框，取消首框后 Apply 3，展开编辑器确认标题保留、其余三行遮盖；一次 Undo 恢复。
- [x] 原生 F 切换 Blur 显示强度控件；Censor 菜单 Home/Return 选择 Solid，实际框选绘制实色并成功撤销。

[原生 Text Only 审阅后应用证据](capture-evidence/censor-text-only-native-20261011.png)。
菜单的坐标点击未可靠执行，改用菜单键盘导航完成实际操作；不据此宣称 VoiceOver 验收完成。
未上传测试数据、未修改共享剪贴板；匿名选区所有编辑已撤销，关闭编辑器与临时页面。
首次 lint 被系统缓存写入权限阻断，正常缓存权限下复验通过，日志 `tinycast-censor-lint-verified.log`。
完整日志为 `/private/tmp/tinycast-censor-suite.log`，Debug/Release 日志同目录 `tinycast-censor-*.log`。

S3c 本阶段完成；S4–S6 和 S1/S2/S2.1 尚未通过的人工、性能及真实工作流门槛继续保留。

## S5 分项推进（2026-10-11）

### 编号及画笔

- [x] 可持久化 Decimal/Roman/Uppercase/Lowercase 格式、1–3999 上限、Next 自定义起始值。
- [x] 编号引线及独立端点拖动；编号圆心作为稳定旋转轴，格式文字按实际字形居中和缩小适配。
- [x] 创建推进序号，撤销/重做恢复序号；文档重开从最后编号继续。
- [x] 新画笔默认二次曲线平滑，Smooth 可切换并更新已选笔迹；旧字段缺失仍画折线。
- [x] 专项验证四种格式、越界值、字母进位、罗马数字、引线坐标变换、JSON、PNG/预览及撤销。
- [x] 原生 AppKit Canvas 事件验证 3999 创建、4000 阻止、引线拖动不移动编号、Undo/Redo 与多点笔迹。
- [x] 完整 112/112 回归（189 秒）、最终 Debug/签名 Release、lint（66 条既有警告）、签名安装及原生操作证据。

首次像素专项在旧折线（Smooth 字段缺失）处发现 PNG/预览最大 3/255 抗锯齿差异；
该旧行为单独按实测 3/255 记录，编号及新增平滑仍通过 2/255 精度。
专项日志 `/private/tmp/tinycast-number-pen-verified.log`，实际 Canvas 事件日志 `tinycast-number-pen-canvas.log`。
新测试诊断行产生的一条行长警告已在完整测试结束后拆行，最终 lint 复检通过。

签名安装记录 `build/install-backups/efficiency-install-22d98379fc.json`，启动 PID 42475。
匿名原生页面从 Roman 28 连续建立 XXVIII/XXIX，Next 变为 30；引线端点拖动后编号位置不变。
撤销端点和第二编号，Next 恢复 29；重做两次恢复 30。格式菜单切换大写与小写，
实际创建 AD/ae 并推进序号；画笔默认 Smooth=1，创建后切为 0 再切回 1。
[编号及画笔原生证据](capture-evidence/number-pen-native-20261011.png)。
CUA 拖动为直线，平滑曲线的实际多点差异以 AppKit 事件和独立 PNG 专项验证为准。
所有编辑已撤销到 Undo 不可用，关闭编辑器、匿名页和临时服务，无复制、保存或上传。

### 文字行吸附与美化预设

- [x] 文字高亮从当前合成输出 OCR 获得行框，生成可持久化普通高亮标注；支持局部/多行、空结果和取消。
- [x] OCR 异步结果核对文档身份及 revision；几何或非高亮内容改变时失效，连续高亮不重复识别。
- [x] 有限内置美化套装，自定义样式保存、覆盖、删除和重启读取；参数超限拒绝，沿用文档 Undo。
- [x] 预设由既有 CaptureSettingsStore 持有；新 SettingsFileKey 及 schema 绑定，避免竞争的持久化所有者。
- [x] 字段与预设测试、最终图像独立解码、识别坐标与各格式一致性、原生证据及安装。

S5 仅在上述两组全部完成后关闭；编号与画笔的专项通过不代替整个 S5 验收。

### 文字行吸附实现记录

Highlight Mode 提供 Freehand / Text Lines，选择后运行已有合成输出 OCR；
水平或矩形拖动以行框中心和行高生成普通高亮，局部选择仅覆盖相交的横向区间。
拖动预览沿用最终标注生成逻辑；多行一次提交，一次撤销。空结果回到 Freehand，
部分结果提示；取消、编辑器身份和 revision 在 OCR 返回后验证。
缓存保存去掉高亮后的完整文档快照，连续高亮及其撤销/重做推进缓存 revision；
其他内容或几何变化丢弃缓存，Undo 不复活旧缓存。

- [x] 局部/多行/反向/无效值/越界裁切、PNG 独立解码与预览、缓存失效专项。
- [x] 实际 AppKit Canvas 多行拖动、一次撤销及 redo、图像调整失效。
- [x] 真实 Vision OCR 行框高亮后文字仍可识别，既有实色遮挡内容仍不可识别。
- [x] 完整回归、最终 Debug/Release、lint、签名安装和匿名原生 Text Lines 交互证据。

首次新专项调用了底层 PNG writer 的错误签名，并出现测试浮点字面量类型不明确；
已改用正式 CaptureRenderer.png 与 CGFloat，专项复验通过，首次失败不算通过。

## S6 设备与 SDK 初查（2026-10-11 04:00）

[本机能力原始记录](capture-evidence/device-capability-20261011.json) 已过滤序列号等标识。
当前连接设备为 Apple M5 Pro / Mac17,8，48 GB；macOS 27.0.1 (26A434)，Swift 6.4，SDK 27.0。
系统清单仅报告一块在线内置 Color LCD；因此目前没有真实多屏或不同缩放显示器验收证据。
现有录屏仍仅暴露 15/30/60 fps。设备型号不等于已证明可稳定录制 120 fps，
未记录持续编码帧时间、音轨同步及资源门槛前，不新增 120 fps 选项。
设备初查不替代 S6 持续录制、摄像头/按键组合、暂停恢复、取消及回收验收。

### 文字行吸附最终交付（2026-10-11 04:03）

完整 113/113 回归通过（194 秒），日志 `/private/tmp/tinycast-highlight-suite.log`。
后续仅修正吸附草稿选框隐藏条件，已有高亮在 Select 下仍显示编辑手柄；
最终 AppKit Canvas 专项通过（26 秒），Debug 和签名 Release 通过，lint 回到既有 66 条警告。
Model import purity 和 diff 检查通过。首次 lint 缺少 Node PATH，补齐后通过；
参数对齐的一条新增警告也已修正，不计入最终警告。

已更新 `/Applications/Tinycast.app`，PID 52866；安装记录 `build/install-backups/efficiency-install-4c6da35eea.json`。
原生 Highlighter → Highlight Mode → Text Lines 成功识别匿名截图；
矩形拖动只高亮前两行局部，第三行保持原样。一次 Undo 移除两行，Redo 恢复；
Select 选中后编辑手柄可见。继续水平拖动高亮第三行，无需重识别；
新增矩形后返回高亮时显示 Freehand，Undo 撤销矩形也没有复活旧缓存。
[匿名原生文字行吸附证据](capture-evidence/text-highlight-native-20261011.png)。
所有标注已撤销到 Undo 不可用，关闭窗口、匿名网页及服务，无复制、保存或上传。

原生复验另发现既有 Canvas 选择较早的标注时会移到标注数组末尾，产生额外撤销记录；
这不影响高亮整次创建的单步撤销，但单击选择不应重排层级，纳入后续修正及回归。
S5 美化预设仍未实施，不能因此关闭整个 S5；S4/S6 和人工性能门槛保持未完成。

## S5 美化预设实施（2026-10-11）

四套有限内置样式 Gradient/Paper/Grid/Window 复用既有 presentation；
应用、保存当前、覆盖及删除均已接入 UI，应用仍经 state.setPresentation 验证尺寸并记录 Undo。
名称 1–40 字符、禁控制字符、忽略大小写判重，上限 20；样式参数必须有限且符合既有范围。
CaptureSettingsStore 是唯一持久化所有者；SettingsFileKey 新增 capture.presentationPresets，
由 AppCore 注入现有 Store 的 binding，schema 不新建所有者。配置备份携带同一类型列表。
导入不合法列表整体拒绝，保持现有预设。旧配置缺少此项时为空列表。

同时修正 Canvas 预览和提交：已有标注就地替换，保持层级，单击选择不产生 Undo；
专项直接使用原生 Canvas 鼠标事件验证较早的高亮不重排、revision 不变化。

- [x] 预设保存/覆盖/删除/重新读取、名称/参数/数量边界、settings binding 专项。
- [x] 四套样式 PNG 独立解码与预览、所有可用格式尺寸/坐标、源图不变、JSON 与 Undo。
- [x] 原生 Canvas 选择无额外 Undo，应用预设可单次 Undo/Redo。
- [x] 完整回归、Debug/Release/lint/纯度、签名安装及原生预设交互/重启证据。

预设导出专项发现既有 CaptureExportOptions.dimensions 误要求 outputBounds 包含在原图 bounds，
留白和窗口边框导致合法美化被拒绝。已改为校验 contentBounds 在原图内、presentation 参数合法，
最终输出继续受 CapturePixelSize 和各格式编码预算限制；新增非法裁剪/参数拒绝回归。
修正后四套样式、全部可用导出格式和 PNG/预览专项通过（24 秒）；首次失败保留，未算通过。


### S5 预设最终验收与菜单修正（2026-10-11 04:26）

完整 114/114 harness 通过（208 秒），日志 `/private/tmp/tinycast-presets-suite.log`。
原生 Canvas 专项确认单击较早标注不重排、不改变 revision、没有额外 Undo；
四套样式的独立 PNG 解码、各导出格式尺寸及遮挡坐标、源像素不变均通过。

安装后的原生检查发现 CaptureToolbarGlyph 的 accessibilityHidden 会让纯图标 Menu
整个控件被隐藏；移除该修饰后，All Tools、Censor、Style、Quick Save 和 Translate
均以有名称的 menu button 出现，All Tools → Image and Recognition → Beautify 实际执行成功。
这修复可访问入口，不代表 VoiceOver 人工验收已通过。
最终布局专项仍通过 63 个组合（5 秒），Debug 和签名 Release 均通过，lint 无新增警告。
首次专项误填 harness 名称，未执行；纠正后通过。首次 lint 缓存权限失败，正常授权复验通过。
Model import purity 和 diff whitespace 检查通过。

原生检查四套内置样式：Paper 的 40/12/12 参数，Grid 配色，Window 的 64/12/24
及窗口边框均正确。Paper 一次 Undo 回到 Gradient，一次 Redo 恢复 Paper。
创建匿名 TinycastQA-20261011，覆盖为 Window，切换 Paper 后重新 Apply 恢复 Window。
退出 PID 66382 并重新启动安装版（PID 66530），匿名预设仍在且应用为覆盖后的 Window。
随后仅删除本次匿名预设，菜单恢复四个内置项；两轮文档均撤销至 Undo 不可用并关闭。
临时匿名网页和本地服务已关闭。

真实 Save As 流程输出 PNG，独立读取为 1888 × 1290，与编辑器一致。
[原生预设界面证据](capture-evidence/presentation-presets-native-20261011.png)，
[实际保存的匿名 PNG](capture-evidence/presentation-presets-export-20261011.png)。
导出 SHA256：eb4febb0a8946c4c0c502b6f47a79b39adb80efec2e54d3e4e487e99bb34cd68。

最终安装为 `/Applications/Tinycast.app`，稳定签名和 designated requirement 验证通过；
记录 `build/install-backups/efficiency-install-1f8b2e896a.json`，旧版已备份。
S5 本阶段完成。整个目标仍未完成：S1/S2 边缘与 VoiceOver、S2.1 物理热键启动与多屏、
S4 真实长截图矩阵和 S6 持续录屏及资源门槛继续保留待验收。


## 用户启动与光标反馈（2026-10-11 07:28）

用户针对物理 Control+1 的启动抖动、选区/工具栏/关闭后的光标询问回复“目前感觉正常”。
据此记录当前主观交互验收正常，不再重复要求用户确认同一问题。
这条反馈不等于已提供连续首帧视频、20 次 P95、真实多屏/不同缩放或色彩仪器结果；
这些独立门槛保持未完成。后续仅会话焦点修正不修改截图冻结背景及选择光标路径。

## S4 真实会话推进与焦点修正（2026-10-11）

[匿名固定头部长页面](capture-evidence/scroll-acceptance-fixture-20261011.html) 是本轮输入，
60 行带唯一编号、颜色和数值，所有资源本地；它是浏览器真实窗口的验收输入，不能替代 ChatGPT/PDF 全矩阵。
普通截图原选区直接进入 Vertical / Horizontal 准备并启动，无需重选。
首次采样被自动化工具的 layer 1000 浮层遮挡，日志明确判为 obscured；
不把这一例记为拼接算法失败或通过，不为自动化新增豁免进程。
无帧 Finish / Cancel 恢复原截图及其尺寸，原图 Undo 不可用，无输出。

原生检查暴露会话控制条不参与 CaptureCoordinator.focusExisting；
新增滚动/录屏控制条的同步焦点方法，保持 nonactivating，不调用 NSApp.activate；
控制条增加语义标题。滚动控制注入当前 metrics，与外部测量及点击区域一致。
114/114 回归通过（207 秒），Debug、签名 Release、lint、纯度和 diff 检查通过；
安装记录 `build/install-backups/efficiency-install-b7b2927245.json`。

原生 Scrolling Capture 控件与 Continue 可访问；系统 open 重新打开安装版后仍显示该控制条，
[重新打开的匿名控制条证据](capture-evidence/scroll-controls-reopen-native-20261011.png)。
该复验继续暴露：重新打开激活 Tinycast 后 Continue 仍以 Tinycast 为前台，立即进入 inactive。
继续及自动滚动现经 coordinator 激活原 targetPID 再 resume，最终回归/安装/复验继续记录。
一次恢复采样后的浏览器自动化交互改变了当前窗口/会话，无法证明生成了新条带；不算拼接通过。

本轮 Arc 新开本机页面已显示，但捕获命令实际恢复的是 ChatGPT 窗口；
不把背景 Arc 截图当作 Arc 实际捕获通过。工具期间出现一次长时间无响应，
随后重新确认测试/构建均终止且成功，未启动重复 runner；输入冲突后核对确为本机 URL 才继续。

### S4 剩余验收矩阵

| 目标 | 手动纵向 | 自动纵向 | 手动横向 | 自动横向 |
| --- | --- | --- | --- | --- |
| ChatGPT 原生内容 | 待测 | 待测 | 待测 | 待测 |
| 浏览器真实页面 | 上版用户仅首屏失败；新匹配版原生待复验 | 待测 | 待测 | 待测 |
| 静态文档 | 待测 | 待测 | 待测 | 待测 |

各例仍要求版本、选区、输入、耗时、输出尺寸、接缝和失败原因；固定头部、重复行、
动态加载、边缘/遮挡、暂停恢复/取消保留、原图/结果返回、标注不烘焙及资源峰值/关闭恢复均不能省略。
已有配置的真实上传授权取消/失败/成功和下载一致性仍待验收，不创建外部账号。


## S4.1 长截图交互复盘与实施顺序（2026-10-11）

已安装 dc7d9523cd 版原生复现：普通选区 → Scroll Capture → 方向/Start Scrolling →
独立双行控制面板。面板固定 680 × 120 点，包含宽文字按钮、尺寸、提示、预览和重选；
与普通截图图标工具栏的密度和风格不一致。无新增内容 Cancel 还会恢复为 expanded editor，
造成退出后又出现另一个框的感受。此次取消/关闭测试无文件输出。
[现状控制条](capture-evidence/scroll-controls-ui-before-20261011.png)。

MacShot 本地 39bcead：OverlayView.startScrollCaptureMode 沿用选区并放行鼠标；
ScrollCaptureHUDView 使用约 36 点高的单行状态/Auto Scroll/Stop；其独立 NSPanel 用于接收控制点击。
借鉴连续的选区与简短控制；不照搬彩色按钮、全局吞 mouseMoved 或可能覆盖采样区的布局回退。

- [ ] 先消除常用路径强制二次 Start；方向保留菜单入口，目标验证失败恢复原状态。
- [ ] 控制面板改为统一截图设计的单行条，稳定锚点；错误按需展开，预览和低频操作收进更多。
- [ ] 取消恢复原展示模式、文档及撤销；完成明确进入结果。保留有内容时的保留/丢弃保护。
- [ ] 原生检查焦点、按键、边缘/刘海、缩放、三尺寸档及状态切换，再安装验收。
- [ ] 以上视觉调整通过后继续真实拼接矩阵；界面改良不代替拼接与资源验收。

此前焦点恢复修正最终检查：114/114（207 秒）、Debug、签名 Release、lint、Model 纯度和 diff 通过。
安装记录 build/install-backups/efficiency-install-dc7d9523cd.json；当前 UI 复现因自动化浮层遮挡暂停，
不将 Continue 恢复采样或真实拼接标为通过。S4.1 尚未实现，不作为已安装功能宣称。


### S4.1 实施记录（2026-10-11）

已实现直接入口及 Vertical / Horizontal / Adjust Region 菜单。手动纵向默认，不自动授权或启动自动滚动。
控制条常态 420 × 46 点，保留 Auto Scroll、Pause/Continue、Finish、More；
暂停原因或显式详情展开额外 72 点，预览默认隐藏。开始前预留展开空间，窗口按 visibleFrame
放置在采样区外，展开时固定顶部和主要按钮位置；空间不足报告错误，不覆盖采样区。

取消保留原 CaptureWorkspaceState 与原编辑器，并重新挂接桌面 overlay；原显示器断开时才
回到窗口编辑器。接受结果、停止、终止路径释放保留的 workspace。启动异步失败恢复原模式。
保留原选区底图会增加会话内存占用，仍须资源矩阵实测，不宣称性能门槛已通过。

首次完整回归 114/114（208 秒）、Debug、签名 Release 通过。随后修正展开锚点及启动失败模式恢复，
最终 Debug 与 lint（原有 66 warnings，无新增）通过；最终回归、签名构建、安装及原生验收继续记录。


### S4.1 安装版原生复验（2026-10-11 07:49）

最终完整回归 114/114（208 秒）；Debug、稳定签名 Release、lint、Model 纯度及 diff 检查通过。
仅原有 AppIntents 元数据 warning；lint 保持原有 66 warnings。
安装记录 `build/install-backups/efficiency-install-a9db6daa8c.json`，PID 18071，
可执行文件 SHA256 `7f530c2dcd2b936cf000cec1790fd61c550dbdbb6b1cb2aaf48e49a5f289347a`。
稳定签名、原 designated requirement 及安装后持续运行均通过，旧版已备份。

- [x] 原选区 1760 × 1130，点击 Scroll Capture 的主按钮直接出现 Scrolling Capture，没有 Start 中间步骤。
- [x] Continue 后出现单行状态/自动/暂停/完成/更多；暂停原因折叠，主要按钮位置稳定。
- [x] 更多菜单可访问 Show Preview and Details / Select Again / Cancel Capture；详情显式展开有预览和尺寸。
- [x] 静态源完成首帧采样，出现 No new content found；不是新条带或滚动接缝通过证明。
- [x] 无新增内容 Cancel 后恢复同一桌面选区 1760 × 1130、Undo/Redo disabled、原截图工具栏，
  未打开 expanded editor；关闭选区无输出。
- [x] 横向菜单实际启动、带原标注取消及撤销/重做通过（见后续原生复验）。
- [ ] 有内容保留/丢弃、三界面尺寸、边缘/刘海及多屏继续验收。

[新单行控制条原生证据](capture-evidence/scroll-controls-compact-native-20261011.png)。
原生窗口初始因自动化浮层遮挡暂停，Continue 后采样；仍保留遮挡检测，不增加工具白名单。
该证据仅证明本轮 UI 与静态首帧路径，整个 S4 真实长截图矩阵、S6 录屏与资源门槛未完成。


### S4.1 横向入口与原标注取消复验（2026-10-11）

安装版 a9db6daa8c：原截图区域 1760 × 1130，画一个矩形，Undo enabled / Redo disabled。
Scroll Capture 菜单实际选择 Horizontal 后直接进入采样，详情显示 Horizontal · 1760 × 1130，
静态源出现 No new content found。该流程不证明横向滚动条带拼接。
[横向控制条原生证据](capture-evidence/scroll-horizontal-controls-native-20261011.png)。
Cancel Capture 恢复原桌面选区与 Rectangle 工具，Undo enabled / Redo disabled；
一次 Undo 后 Undo disabled / Redo enabled，Redo 后恢复原状态，再 Undo 清理并关闭，无保存/上传。
因此横向菜单启动与带原标注取消的撤销/重做本轮通过；有新增条带的保留/丢弃仍待测。

边缘代码检查发现 NSScreen.screens 顺序可能优先主屏，使外接屏选区的控制条跳到主屏。
修正为当前捕获屏 visibleFrame 优先；滚动 collapsed/expanded 几何由同一布局策略计算，
保持顶部/横向位置固定。新增三档缩放 × 两套坐标 × 九个边缘位置（54 例）、全占区域拒绝、
外接屏优先的几何检查。真实多屏、刘海和三档原生渲染仍不以数学测试代替。


### S4.1 显示器布局修正版交付（2026-10-11 07:58）

新增几何检查通过，单项 capture-workflow-test 41 秒；最终完整 114/114 通过（206 秒）。
Debug、稳定签名 Release、lint、Model 纯度及 diff 检查通过，无新增 warning。
后台更新 `/Applications/Tinycast.app`，安装记录 `build/install-backups/efficiency-install-840207f5d9.json`，
PID 27951，SHA256 `e5083c9562a4cfec09152d09679d1e53199666f9f1d82370b66d32a2fbc5ed68`；
同一稳定 designated requirement，旧版已备份。此最终显示器顺序修正仍待原生多屏复验，
上一个安装版的横向/标注取消原生证据保留其原版本范围，不自动扩大为本版全矩阵通过。

[取消后的空闲 RSS 快照](capture-evidence/scroll-cancel-idle-rss-20261011.json)：a9db6daa8c 主进程
168,296,448 bytes，自有 helper 无活动进程。没有同步五秒边界、同进程冷基线或 20 轮采样，
不据此宣布内存回收/循环 gate 完成。下一轮真实 PDF/浏览器滚动需占用桌面，已询问可用时间，
未得到答复前继续不占桌面的检查；当前目标保持进行中。


## S6 录屏取消与收尾恢复补齐（2026-10-11）

代码审查确认控制条只有 Pause/Stop，缺少 S6 取消验收的入口；finish 成功而后续 inspect 抛错时，
session.phase 已为 finished，原 UI 只显示永久 ProgressView，无法重试。
新增 More Recording Actions / Cancel Recording：先暂停，再对已有片段提供 Back / Discard / Keep Result，
Back 保持暂停，Keep Result 仅打开预览，不执行用户配置的自动保存/复制；Discard 回到原桌面截图与撤销栈。
原 scrollReturnWorkspace 改为语义明确的 retainedWorkspace，由同一 coordinator 管理两类会话。
录屏开始保留原 workspace，接受视频结果/停止/终止路径释放；显示器不再可用时返回窗口编辑器。
Recorded 状态提供 Retry Opening Recording，Starting/Pausing/Finishing 分别显示真实状态。

首轮 Debug 和 lint 通过；最终检查与签名安装继续记录。取消保护、摄像头/音轨释放和结果重试的原生
验收均未完成，不能因为新增入口或编译成功将 S6 标为完成。桌面占用询问仍待用户答复。


### S6 构建交付与 PDF 原生验收尝试（2026-10-11 08:10）

完整 114/114 通过（206 秒），Debug、稳定签名 Release、lint、Model 纯度与 diff 检查通过，
无新增 warning。已安装 `/Applications/Tinycast.app`，记录
`build/install-backups/efficiency-install-64e7e13508.json`，PID 34999，
SHA256 `0580f198166b0f8e26be6519dd6d96ec8491923811b5351ebb49d06050360cae`；旧版已备份。
录屏取消/保留/重试的原生结果仍待验收。

用户回复桌面可用后，用匿名 60 行 PDF 在 Preview 全屏实际尺寸下执行截图，
确认底图为 PDF ROW 029–032，选区 2530 × 1580；Scroll Capture 主按钮直接进入控制条。
采样被遮挡保护暂停，日志确认 target PID 35030 / window 8122，遮挡为
SkyComputerUseService PID 35042 / window 8143，最终 layer 3，bounds 879/843/126/126 pt。
此为自动化辅助窗口的真实遮挡，未新增进程白名单、未放宽保护，也未获得拼接条带。
More → Cancel Capture 返回原截图选区与禁用 Undo/Redo，随后关闭截图及匿名 PDF。
因此本版直接入口/取消返回通过，真实 PDF 拼接仍未通过，不能以该轮代替 S4 完整矩阵。

[验收前提](capture-evidence/acceptance-prerequisites-20261011.json)显示当前仅一块在线内建屏，
没有配置上传目标，未读取任何上传凭据；真实外接/混合缩放与三服务上传验收仍缺前提。
目标保持进行中。


### S4/S6 保留对话框取消语义修正（2026-10-11）

代码核查发现 DialogController.choose 约定最后一个 option 是 Escape/失焦的取消项，
Capture 的五处调用却将 Cancel/Back 放在第一个。结果录屏取消、截图/视频关闭和长截图取消
可能在 Escape 时走保留/保存分支；重新选区对话框还可能走 Discard and Reselect。
统一调整为显式保留/保存、丢弃、最后 Cancel/Back，默认确认仍保留/保存，映射分支同步修正。
长截图对话框返回后核对 session 身份与任务取消；录屏 finish/inspect 返回后核对取消和 session，
关闭保存对话框返回后也拒绝取消任务或过期视频，避免迟到结果展示或自动输出。
Debug、lint 初查通过；最终完整回归和稳定签名 Release 继续执行。
这些是源代码可证实的缺陷和修正，Escape/失焦的完整原生矩阵仍待实际验收。


最终回归 114/114 通过（211 秒），Debug/稳定签名 Release 通过，仅已有 AppIntents metadata 提示；
lint、Model 纯度与 diff 检查通过。08:15 已后台更新 `/Applications/Tinycast.app`，
安装记录 `build/install-backups/efficiency-install-8a26f830ae.json`，PID 43585，
SHA256 `6b8e3c4e127bcf0015101e0189cdf2cf6cf69be320bddc7954865e90338deb96`。
同一签名 requirement，旧版备份保留。当前安装版的对话框 Escape/失焦和录屏取消/重试
均未获得原生通过证据；用户手动真实长截图反馈已询问，尚待回复，S4/S6 不标完成。

### S4.2：用户实测缺陷与连续体验修订（2026-10-11）

用户实测固定页头浏览器滚动后只有第一屏，当前长截图真实拼接验收不通过，不能以模型测试替代。
匿名真实浏览器两帧复现文本栅格化导致 uncertain；5×5 匹配描述符平均后保留原置信度门限，
原始描述符单独判定固定页头/页尾，避免平滑改变边界；输出 strip 逐行像素一致。
修订后 capture-workflow-test 通过，仍需新版本原生复验。

- [ ] 直接选区到采样无中间准备界面，异步准备期间保持原浮层，失败恢复原编辑。
- [ ] 长截图工具栏共用普通截图视觉及按钮尺寸，移除两处常驻操作口号。
- [ ] 自定义原生拖拽排序、选择工具锁定、搜索禁排、持久化及无障碍替代。
- [ ] 主保存改为另存为；快速保存目录可找，反馈明确；检查快捷键实际事件分发，包含文字编辑状态。
- [ ] 完整测试、Debug 无新增警告、lint、稳定签名 Release 安装及原生复验。

用户新增反馈：菜单标注的保存快捷键似乎不生效。检查发现菜单仅在标题写快捷键，未绑定；
窗口也在文字编辑器为第一响应者时跳过全部命令处理。本轮添加实际菜单绑定，保存命令优先处理；
剪贴板/撤销仍尊重文字编辑器，原生快捷键验收待执行，不能据代码检查宣称已通过。

S4.2 本轮实现与安装记录：

- 上述五项已落代码。保存按钮为 Save As；⌘S 快速保存、⇧⌘S 另存为实际绑定，
  在第一响应者为文字编辑器时优先分发保存命令；保留文本复制/撤销行为。
- 完整 114 harness 通过（207s），最终 Debug/Release 编译成功，仅既有 AppIntents 元数据提示；
  lint 通过、无新增警告，Model UI import 检查为空，diff whitespace 检查通过。
- 2026-10-11 08:34:23 本机安装 `/Applications/Tinycast.app`，PID 54748，稳定签名与原 DR 相同。
  收据 `build/install-backups/efficiency-install-bc5cec9611.json`；旧版完整备份保留。
- 证据：[S4.2 验证记录](capture-evidence/continuity-verification-20261011.json)。
  原生拖拽、保存快捷键（含文字编辑）、工具栏与切换体验、真实多屏滚动拼接均待复验；
  上一安装版本“仅第一屏”的用户失败记录继续保留。本轮未将 S4/S6 或整个目标标为完成。

### 完成审计及正文选区回归（2026-10-11）

[完整完成审计](capture-completion-audit.md) 按产品阶段、AC-01…AC-15 和资源 Gate 记录证据范围。
本轮增加去左侧、正文子区、去固定页头三类真实浏览器裁剪，发现上一安装版不能覆盖这些场景。
稀疏采样会混淆相似段落，恰好相同的底部空白也可能误判固定页尾。
实施密集候选复核、局部文字块歧义检查及固定区域辨识，误差上限和歧义数字不变，
保留全通道一致性及遮挡规则；追加完全重复内容必须 uncertain 的安全回归。
诊断输出四种选区均得到279–280px位移；正式 harness、完整回归及新安装尚在验证，不计原生通过。

正文回归正式 harness 已通过（41s，编译39.1s），新增完全重复内容拒绝与三个真实裁剪选区。
模型匹配[20样本计时](capture-evidence/scroll-region-model-timing-20261011.json)在四种选区的
nearest-rank P95 分别约9.1/9.1/10.7/12.3ms。仅为预加载描述符的 shipped policy，
不含 SCK、读帧、UI、预览和输出；测量时有编译任务，不关闭原生500ms或内存Gate。

正文匹配最终交付：2026-10-11 08:50:09 安装稳定签名 Release，PID 67656，
收据 `build/install-backups/efficiency-install-7cc4a7d8dc.json`。完整114/114（206s）、
Debug/Release、lint、Model纯度及diff检查通过；旧版备份保留，DR不变。
[最终证据](capture-evidence/scroll-region-verification-20261011.json)只证明模型/真实帧裁剪回归、
最终构建及安装。原生快捷键、拖拽、整体滚动与资源矩阵继续待验，整个目标保持未完成。

2026-10-11 原生保存复验：[保存证据](capture-evidence/save-shortcuts-native-20261011.json)。
普通截图选区下 ⇧⌘S 打开另存为，取消后返回原选区；主保存按钮同样打开另存为并导出900×550 PNG。
文字仍在编辑时 ⇧⌘S 可打开保存面板，⌘S 可快速保存至 Pictures/Tinycast。
新建单条 `SAVE SHORTCUT OK` 标注后直接⌘S，独立解码900×550输出并目视确认文字完整。
先前两条文字重叠导致OCR无法识别的试次不作为内容丢失结论。
以上关闭普通截图保存快捷键复验项；长截图结果编辑器、工具栏拖拽及完整产品矩阵仍待验。

2026-10-11 09:07 补验长截图返回路径：匿名 PDF 选区2500×1230，进入长截图控制条后
因自动化光标辅助窗口遮挡而暂停；点击完成返回原截图工作区，⇧⌘S打开另存为，
[保存面板证据](capture-evidence/scroll-return-save-as-native-20261011.png)显示2500×1230。
取消后⌘S显示实际保存目录；独立全图解码导出PNG为2500×1230。
该试次只证明长截图返回后的保存快捷键，不证明新增滚动条带或拼接成功。
工具栏勾选能更新预览，测试中椭圆恢复隐藏；原生自动化拖动未得到顺序变化，
拖拽排序保持未验收，不因已有onMove实现而关闭该项。

2026-10-11 09:13 工具栏补充原生 List 多选状态、行标识及整行命中区域，切换分组或搜索清除选择。
完整114/114（204s）、Debug/稳定签名Release、lint、Model纯度和diff检查通过。
安装收据 `build/install-backups/efficiency-install-ccf20f8bb2.json`，PID76518，
SHA256 `5e28997e1594144f5e65c7341fdd4189cc8ad8fc65a3e8bf94420d64b3ef01f5`。
原生整行点击将Text标记为selected，已记录[选择反馈](capture-evidence/toolbar-row-selection-native-20261011.png)。
随后自动化drag仍未改变顺序，因此该实现增量不关闭拖拽验收；不将行选择等同于排序成功。

2026-10-11 09:24 当前安装在 Preview 匿名 60 行 PDF 上完成真实纵向长截图：
初始1700×1000，手动小步滚动新增到1176、1353高，再自动滚动累计29段、1700×6033。
暂停及完成日志与控制条尺寸一致，证据见 `capture-evidence/scroll-pdf-native-20261011.json`。
大幅四步跳动曾触发 uncertain，回滚后恢复；遮挡保护曾识别自动化辅助窗口，未绕过。
完成后 Tinycast 结果窗口的 CUA 读取持续报 ScreenCaptureKit -3811；重置自动化仍未恢复，
Preview 仍可读取。多段结果另存为、实际PNG导出、独立行序与接缝核对保持待验，保留未保存结果。

拖拽诊断补充：09:18 原生主线程采样停留于 `_tryCatchDragUntilMouseUp`，Escape 后恢复。
因此之前 CUA drag 的未变序现象可能是拖放手势未结束，不能据此断言产品排序失效；
也不能把已启动原生拖动当作成功落位，物理拖拽验收继续保留。

当前后续候选补齐长截图累计尺寸的 accessibilityValue，提供实时宽、高及像素单位；视觉不变。
Debug、Release、lint、Model纯度及diff检查通过。完整114项中113项通过、视频测试运行300秒超时；
构建完成后仅复验视频，9秒运行通过（含编译31秒）。保留完整轮次的失败，不写作114项一次全绿。
候选二进制SHA256为 `337e2da70495c04ee6ae11228aec20bfbb8817058a95e41dde4321842feef99a`。
未替换当前安装，以保留尚未导出的29段长图；源码候选的无障碍原生复验及安装仍待完成。
工具条暂停时日志出现NSHostingView重入布局告警；源码在onChange中同步setFrame(display:true)，
尚未独立证明因果，不把此告警直接归因为用户所述启动抖动，后续须专项复验。

用户确认窗口可见后读取恢复。前版29段结果取消另存为后CmdS导出1700×6033，
独立完整解码及Vision识别ROW001–012连续；标题像素带间距531/532，无明显断层。
前版面板Save与New Folder曾禁用，换目录/尺寸无效；保存服务有错误日志，但因果未证实。
10:34安装已签名候选409c288e49，PID96097，二进制337e2da70495散列见完整安装收据。
从历史重开同一flattened长图，ShiftCmdS打开另存为且Save启用，导出原始PNG成功。
两个输出SHA256均为 `2a33a93c699320843a8a1942c6d2f879bba1cec03a8525dc9d66a16ba84f5206`。
这关闭重开长图的快捷键/另存为输出检查，不冒充当前版本新建多段会话和完整资源矩阵。
当前窗口读取阻塞已解除；尺寸accessibilityValue的实际长截图控件复验仍待进行。

409c安装版后续原生排序验收：Annotations中Arrow两次Move Up，预览变为Select/Arrow/Text，
Done后重开仍保持；Select移动禁用，搜索arrow时移动禁用。Move Down恢复原顺序。
Capture and Output中Save As上移更新动作预览，注释顺序不变；下移并重开恢复。
只读比对bundle偏好的order和可见items，均与测试前一致；未保留任何测试布局改动。
证据见 `capture-evidence/toolbar-menu-reorder-native-20261011.json`；不关闭物理拖拽与VoiceOver朗读项。
当前源码不与构建并行的完整测试114/114一次通过（203秒），日志
`/private/tmp/tinycast-installed-409c-full-tests.log`；此前视频超时记录继续保留。
新建长截图复验未完成：Preview已有窗口在Stage Manager外侧不可点击，Open面板的打开按钮禁用，
取消和读取随后超时。Tinycast设置与自定义面板仍能操作，不判定Tinycast全局失去响应。

用户确认取消面板并显示PDF后，CUA响应恢复但仍返回Open面板；重置绑定也未对齐。
Cancel、选中匿名PDF并调用其打开动作、Return均未得到文档窗口，Open持续禁用，
Window菜单无PDF条目。记录为用户可见状态与自动化绑定不一致，不认定为Tinycast缺陷。
本轮没有新增原生通过项，未改源码或重复构建；直接多段另存为及尺寸AX复验仍待完成。

用户实机确认：完成长截图进入编辑器后，Shift-Command-S正常打开另存为；未提供实际文件保存结果。
先前重命名窗属于Preview，采集时键盘焦点仍在源应用。新增单行等大保存按钮Finish and Save As，
复用停止采样、结果编辑器与原另存为流程，避免用户为保存而判断焦点；取消保存保留结果。
停止等待后核对取消、会话及源身份；保存使用同一受控任务，避免嵌套run被忙碌门禁忽略。
该新增入口的构建、安装与原生验收待完成，不全局拦截源应用保存键。

本轮完成：新增按钮沿用共享字形与等大单元，停止等待后核对取消、会话/源身份，
在同一受控任务内打开另存为；采集前首帧尚未就绪时禁用保存。12:11签名安装1ccce67537，
SHA256 6854a6d21572a76fbfd65bc84af56ef8224fd5914c7ef36407f5b70f4aaa4d01。
最终完整114项203秒通过、Debug/Release无新警告、lint/Model纯度通过。
原生首帧前禁用/首帧后启用，27段自动纵向采集520×5540，一键另存为并保存PNG，完整解码通过；
前一候选34段520×6800另存为Cancel后结果保留、快捷键重开再保存也通过。
窄正文区域视觉行号有序；保留初始大选区被自动化辅助窗遮挡、空会话无保存反馈的失败记录。
证据见scroll-direct-save-verification、scroll-direct-save-ready-output；旧版暂停时重入布局警告
仍待定位。完整场景、性能/资源、多屏及上传等Gate继续保持未验收，不收窄原计划。

布局告警继续处理：当前1ccce67537安装版12:12:25暂停时复现NSHostingView重入布局，
日志`/private/tmp/tinycast-scroll-layout-baseline.log`。候选将状态更新中的面板setFrame改为
display:false，保持同步几何与原锚点，让AppKit按正常显示周期绘制；不新增异步状态或延时。
根因及修复效果待同机多次暂停/恢复、详情展开/收起的原生A/B与进程日志核实。

12:26原生A/B否定首个候选：5d813e59b3安装版连续三次暂停/恢复均可响应，
但仍出现6条重入布局告警（scroll-layout-native.log），display:false不足以修复。
第二候选删除SwiftUI onChange中的窗口调整，改在session暂停/恢复回调与详情Binding setter
同步调整面板；关闭时清理回调。Debug已通过，完整套件、Release及同机原生复验待完成。

12:35第二候选df68327e8e已稳定签名安装，SHA256
01b8b2a7d26b44ad32e6d5b399ae72fcf3dbe74dd3218d4adc49fbb0737b389b。
完整114项211秒通过，Debug/Release无新增警告，lint/Model纯度/diff检查通过。
同机原生三次暂停/恢复完整展开收起，当前PID45246重入告警为零；随后自动滚动10段，
一键另存为实际保存520×2480 PNG，完整解码及窄正文视觉行序正常，结果已关闭。
详情菜单首次动作曾使自动化绑定到边框窗口，第二候选尚未完成详情切换复验；该项继续开放。
首个候选display:false仍有6条告警的失败证据保留；不把本轮范围扩写为完整S4或总体通过。
证据见capture-evidence/scroll-layout-verification-20261011.json。

12:39–12:42同一df68327e8e安装版继续原生验收：实际点击省略号后详情菜单可读，
预览/状态/方向尺寸展开为560×220像素，收起为560×76，过程无重入布局告警。
匿名PDF自动追加11段520×2660，Cancel→Back保留尺寸及暂停状态，Cancel→Keep Result
进入结果；ShiftCmdS另存为实际保存，独立完整解码通过；Back to Screenshot回到520×860，
Scrolling Result回到520×2660，保存结果已关闭。详情布局专项通过不代表全场景完成。
另建带箭头标注原图（Undo可用），追加至520×5180后暂停，准备验Discard恢复；
AX菜单动作后自动化绑定装饰边框，尚未执行Discard，不推测标注或撤销已恢复。
会话保持，不重启清除，已请求控制条取得焦点；证据见scroll-details-cancel-verification。

资源验收工具继续核查：capture-memory.py此前延迟用整段日志正则，会混入其他PID/旧会话，
进程树仅计包内后代，会漏掉重新托管helper及包外子进程。现统一关闭/延迟的PID、category、
采样时间范围，按时间排序，只匹配完整事件消息；采样包含同包helper及全部已识别后代，记录PID。
新增Scripts/test-capture-memory.py专项2项通过：400条其他进程快事件不能掩盖本次20条慢事件，
旧/未来/category不符事件排除；重新托管、包外后代及无关进程归属有独立断言。
Debug和lint已通过，完整套件运行中。未进行真实资源采样，不把脚本修正记为资源Gate通过。
已安装app运行代码无变化，保留当前暂停会话，未重装；包外非后代服务仍需实证归属并统计。

资源工具修正后完整114项203秒一次通过；Debug无新增警告、lint、diff及Model纯度通过。
已安装app散列复核仍为01b8b2a7…，没有运行代码变更或重装；当前Discard反馈仍待用户操作。
