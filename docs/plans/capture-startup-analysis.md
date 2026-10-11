# 截图启动接管分析

日期：2026-10-11。依据：本地 MacShot `39bcead` 与 Tinycast 当前工作区；未做同机时序对比。
目标：点击截图后，桌面内容的位置、比例、清晰度和颜色稳定，只出现必要的光标与操作提示。
静态桌面冻结可以无感；视频、动画等动态内容冻结必然停止，不能承诺所有背景完全无感。

## 结论

MacShot 同样先获取整屏图片，再在冻结图片上选区，不是依靠实时屏幕直接截取小图来避免抖动。
Tinycast 的问题在接管路径与呈现策略。上一轮禁用系统窗口动画是必要修复，但不足以完成验收。

| 环节 | MacShot 本地实现 | Tinycast 当前实现 | 判断 |
| --- | --- | --- | --- |
| 取图 | macOS 26 rect API，绕过 ShareableContent 枚举 | 先枚举应用/窗口并建立排除自身的 filter | 热路径成本不同；rect 不可直接替换，必须保留排除自身窗口语义 |
| 图片呈现 | CGImage 装入独立 CALayer，设置 backingScale，禁用图层隐式动画 | NSView.draw 绘制原图、遮罩、选区与像素提示 | 应分离固定底图和交互层；draw 本身不能证明一定抖动 |
| 窗口 | 每屏控制器池，复用并预热 WindowServer 表面 | 每次销毁并新建窗口及 SwiftUI 宿主 | 首次创建与布局留在热路径；应比较首次和后续启动 |
| 图像到显示 | 图片安装后直接展示 | 图片获得后等待所有源瓦片写入，之后才展示 | 冻结帧与实际桌面的时间差被拉长，动态背景可发生回跳 |
| 桌面外观 | ignoreShadows=false、displayIntent=.local | ignoreShadows=true、displayIntent=.canonical，窗口固定 sRGB | 外观一致性风险；不等于已证明空间抖动原因 |
| 遮罩 | 默认 45% 黑，可关闭选区外阴影 | 无条件绘制 35% 黑，包括尚未拖选时 | Tinycast 必然有亮度跳变；MacShot 默认压暗也不满足本任务的最小扰动目标 |
| 多屏 | 光标屏先取图先显示，后续屏不抢走键盘 | 普通选区仅主目标有底图，但所有屏都出现遮罩；换屏重新准备 | 非目标屏仍为实时背景加遮罩，需明确一致接管策略 |

## 优先实施顺序

1. 底图接管与文档存储拆开：先让原始图片稳定显示；源瓦片准备由会话持有，完成前按真实就绪状态
   控制编辑、OCR、导出等依赖。不得伪造可用文档，不得让旧会话异步结果进入新会话。
2. 固定图片层与交互层分离：原始 CGImage 只安装一次，几何与 backingScale 在显示前确定；
   显式禁用窗口及图层动画。鼠标移动仅改变交互层，不重绘整屏底图。
3. 复用已初始化窗口和工具栏宿主，关闭时释放图片/画布/会话引用，屏幕配置变化时重建。
   不照搬 MacShot 0.001 alpha 预热；任何预热均不能闪屏、抢焦点、吞鼠标或提前申请截图权限。
4. 验证显示用图片的 local intent、色彩标签及阴影；导出继续将源像素归一化为 sRGB 瓦片，
   不因显示优化改变导出、取色、OCR 与隐私遮挡约束。先用真实屏幕验证，再决定参数迁移。
5. 按本任务目标调整遮罩：待选阶段保持背景原貌；开始拖选后才在选区外提供必要的轻量遮罩。
   这项是针对 Tinycast 的产品取舍，不能称为复制 MacShot 默认行为。
6. 将窗口枚举移出不需要窗口选取的关键阶段；评估 rect API 的自身窗口排除语义，再决定是否采用。
   不移入旧系统 CGWindowListCreateImage fallback，不引入旧系统兼容层或 MacShot 单例。

## 验收与证据

- 同一静态文字/单像素网格背景，记录取图、底图安装、首帧可交互和瓦片就绪时间；分别测首次和连续启动。
- 物理 Control+1 + 外部高帧率视频：排查缩放、位置位移、模糊到清晰切换、重影和意外亮度跳变。
  不用 AppKit 的显示函数返回时间冒充 WindowServer 实际上屏时间。
- Retina/外接屏/不同缩放和屏幕布局、暗亮背景、窗口阴影；多屏不能有黑边、错位或抢键盘。
- 快速启动取消再启动、存储失败、源图尚未就绪时操作、完成后立即关闭，验证取消及源文件租约。
- 系统实时光标与截图内光标必须区分；预览不能出现两个光标，导出遵守原光标偏好。
- 当前没有新版 MacShot 同机性能数据。旧仓库证据不能当作这次安装的耗时；本轮日志未检出
  CapturePerformance 事件，因此不填估计耗时。根因仍需通过首帧序列定位，不能把上述每个风险都写成已证实原因。

## 源码入口

- MacShot：`macshot/AppDelegate.swift:443`（池）、`:1385`（捕获）、`:1538`（安装显示）。
- MacShot：`macshot/UI/Overlay/OverlayWindowController.swift:19`（独立底图层）、`:218`（不透明窗口）、`:283`（预热）。
- MacShot：`macshot/Capture/ScreenCaptureManager.swift:223`（rect API 与 local/shadow 参数）。
- Tinycast：`Tinycast/Features/Capture/UI/CaptureCoordinator+Workspace.swift:33`（取图后写瓦片再显示）。
- Tinycast：`Tinycast/Features/Capture/UI/CaptureOverlayController.swift:9`（每次创建窗口）。
- Tinycast：`Tinycast/Features/Capture/UI/CaptureSelectionView.swift:148`（绘制底图与固定遮罩）。
- Tinycast：`Tinycast/Features/Capture/Service/CaptureScreenService.swift:48`（捕获配置）。
