# WebP 导出方案，已批准

2026-09-29。用户已明确选择 B，批准官方 libwebp 依赖例外；本方案进入实现与验收。

## 建议

建议为 fork 接受一个明确的依赖例外：内置官方 libwebp 静态编码组件，接到现有图片导出。
长期补齐 Macshot 的图片能力，不能依赖系统何时增加编码器。用户只会多一个导出格式，无需独立转换流程。

| 方案 | 用户体验 | 工程与维护 | 结论 |
| --- | --- | --- | --- |
| A：继续 ImageIO、PNG/JPEG/HEIC/AVIF | 当前流程完整；没有 WebP 导出 | 继续零依赖，维护最少 | 可选，但须明确保留该缺口 |
| B：内置官方 libwebp 静态编码组件 | Save 中直接选 WebP，离线可用 | 一个第三方依赖及版本更新责任；沿用 XcodeGen | **推荐** |
| C：照搬 Swift-WebP 包链 | 与 B 同样便捷 | 多一层 Swift wrapper 和间接包版本 | 不推荐为薄封装增加包链 |
| D：调用外部 cwebp 或在线转换 | 需要安装、配置或上传等待 | 环境差异和失败恢复更复杂 | 不作为产品默认能力 |

Macshot 本地 `ImageEncoder.swift` 调用 Swift-WebP 的 RGBA 路径；其 `Package.resolved` 锁定
Swift-WebP 0.5.0 → libwebp-Xcode 1.5.0。它不是只用 Apple API 实现 WebP。
Tinycast 已观察到 ImageIO 能读取 WebP，写入列表没有 WebP；不能把读取标为支持导出。

## 批准 B 后的落地

1. 固定官方发布源码、校验值和来源，保留 COPYING/PATENTS。2026-09-29 复核官方
   [NEWS](https://github.com/webmproject/libwebp/blob/main/NEWS) 顶部发布仍为 1.6.0；该源码已固定在 Vendor，
   208 个文件与官方归档逐字节相同。版本和归档 SHA-256 见 [Vendor 说明](../../Vendor/README.md)。XcodeGen 管理静态 C target，不加入 SwiftPM、运行时下载或 Homebrew 前置。
   包含编码所需组件与写 ICC 所需的官方 mux；图片导入继续使用系统能力。
2. `CaptureExportOptions.Format.webp` 接入现有 Save；`CaptureRenderer` 取得同一 revision 的最终像素，
   由小型 `CaptureWebPEncoder` 适配 C API。Model 只存值，不增加 coordinator、actor 或全局状态。
3. 明确 pixel width/height/stride、straight RGBA；最终像素在 `CaptureWork` 中渲染，编码由短生命周期
   `CaptureWebPHelper` 完成。progress hook、进程取消及超时共同回收任务；helper 退出后原子替换临时文件，
   取消/失败保留原文件。既不在主线程编码，也不让编码器空闲内存长期留在主进程。
4. 默认、Copy、历史最终图和 OCR 继续 PNG；WebP 只用于明确选择的文件输出，避免每次复制都等待编码。
5. 固定版本、跟进官方安全修订，每次升级跑像素和资源回归并记录包体增量；不预报未经测量的 KB 数或压缩率。

官方高级编码 API 支持有损/无损配置，质量 100 不等于无损。
[官方 API](https://developers.google.com/speed/webp/docs/api)

## 保持简洁的交互

- Save → Format: WebP；选中后才显示 Compression: Lossless / Lossy，默认 Lossless。
  Lossy 显示质量，沿用现有质量初值 92%。文字截图优先清晰，不另做设置页。
- 单边最大 16,383 像素。超限时在当前面板提示“选择 PNG 保留原尺寸，或修改尺寸”；不静默缩放、截断或转动画。
  这是格式限制。[官方尺寸说明](https://developers.google.com/speed/webp/faq#what_is_the_maximum_size_a_webp_image_can_be)
- 首版沿用现有非流式格式的 4 MP 输出保护，与格式尺寸限制分别说明。1600 × 30000 长图选 25% 后为
  400 × 7500，可在该预算内输出 WebP；需要保留原尺寸小字时用 PNG。提高 4 MP 限制须另做资源实测。
- 当前源 tiles 已统一成 sRGB；P3 导出按现有流程转换并写 ICC，不声称恢复导入时未保留的广色域。
  ICC 使用标准容器字段。[官方容器规范](https://developers.google.com/speed/webp/docs/riff_container)

## 退出标准

- 深浅色文字、半透明边缘、透明像素、遮盖、P3 转换、奇数宽度和 Retina 像素分别独立解码；防止预乘 alpha 误用产生黑边。
- 无损输出比对最终 RGBA，配置 exact 保留透明像素 RGB 的既定契约；有损输出记录误差和小字识别差异。
  不承诺 WebP 一定小于 PNG。[透明像素与大小差异](https://developers.google.com/speed/webp/faq)
- 4 MP / 16,383 边界、取消、磁盘失败、旧文件保留、30 次编码释放、当前 Spec 图片场景预算通过。
- 用本项目同一批截图比较 PNG/AVIF/WebP 体积和耗时，再决定默认推荐，不拿官网平均压缩率代替产品数据。
- Debug/Release、签名、全部 harness、通知文件和发布源码一并验证。

库使用 WebM 的 BSD 风格软件许可，分发应保留对应通知；实施时按随源码携带的文件落实。
[官方软件许可](https://www.webmproject.org/license/software/)

决策已关闭：用户明确接受 B。AGENTS.md、README 和 NOTICE 已记录唯一依赖例外，其他依赖仍需单独判断。

## 本轮落地记录

已接入 XcodeGen 静态 target 与 standalone harness；Save 的 WebP 显示 Lossless / Lossy，
后者才显示 Quality。超限提示留在当前保存面板，校验使用 Apple 支持的
[文件名确认 delegate](https://developer.apple.com/documentation/appkit/nsopensavepaneldelegate/panel(_:userenteredfilename:confirmed:))，
而不是依赖被系统远程面板绕过的 NSSavePanel.ok override。最终是否写出仍由同一 Model 校验保护。

`capture-webp-test` 已验证 73 × 61 奇数宽度、透明度、实色遮盖、sRGB/P3 ICC、30 次编码与取消/失败保留旧文件；
无损独立解码后的预乘 RGBA 与 PNG 最大容许差 1，覆盖色彩/预乘往返舍入。4 MP 压力和原生面板结果另行记录，
不能将这个小图循环当成完整内存 gate。

真实 Save 面板已完成 1600 × 30000 的两层超限提示：原尺寸超单边限制、50% 超 4 MP，
点击 Save 均保留面板；25% 为 400 × 7500，可成功保存无损及质量 92% 的有损文件。
首轮无损 27,810 bytes，与同尺寸 PNG 的 RGBA 完全一致；有损 31,990 bytes、最大通道差 10。
ICC 为 3,144 bytes。验收后恢复 PNG / Original pixels / sRGB / Lossless。

有损不保证比无损更小，因此界面最终使用准确的 `Lossless / Lossy`，不再使用 `Smaller File`。
初轮小字样本的无损为 11,978 bytes，PNG 为 42,230 bytes，有损为 18,344 bytes；
八行 12/14 px 中英文、深浅底、混排及重复行的独立 Vision 识别一致。
以上为第一轮配置的质量证据；下面的内存定位之后改用无损 preset 1，最终复测单独记录。

### 内存定位

混合基准同时包含导入、PNG/AVIF/WebP 编码、独立 ImageIO 解码及逐像素比较，
其高噪声进程峰值约 1.11 GB，不能直接归因为编码器，也不能用于声明应用预算通过。
新增按格式独立进程的 encode-only 模式后，首轮 4 MP 高噪声无损连续 30 次为 348.2 MB，
仍需优化。官方参数对照保持像素精确；preset 0 虽更省内存，却把小字样本放大为 364,848 bytes，
故未采用。选择 preset 1，提前释放画布与编码输入，避免重复 sRGB 转换及两份完整输出复制。
`WebPMuxCreate` 借用的 writer 在 mux 完成前保持存活，最终文件缓冲也在同步写入后才释放。


### 最终独立编码复测

相同机器、相同输入、优化构建的 shipped source；每种格式独立进程，不在导出内存测量中调用 ImageIO 解码。
PNG/AVIF/有损为单次，无损为 30 次中位数。像素核验在另一进程进行。

| 输入与格式 | 文件 bytes | 编码毫秒 | 独立进程最大 RSS |
| --- | ---: | ---: | ---: |
| 720 × 4200 小字 PNG | 42,230 | 132 | 14.9 MB |
| 同图 AVIF | 15,310 | 531 | 138.1 MB |
| 同图 WebP 无损 | 11,822 | 34 | 84.3 MB |
| 同图 WebP 有损 92% | 18,344 | 216 | 56.9 MB |
| 2000 × 2000 高噪声 PNG | 13,737,535 | 723 | 27.3 MB |
| 同图 AVIF | 4,499,070 | 442 | 198.8 MB |
| 同图 WebP 无损 | 12,003,250 | 178 | 267.7 MB |
| 同图 WebP 有损 92% | 3,522,894 | 886 | 98.2 MB |

两种最终无损 WebP 与 PNG 的独立 RGBA 比对完全一致。无损高噪声的峰值由首轮 348.2 MB 降至 267.7 MB；
这仍是独立编码进程数据，不能直接相加为 app 峰值，也不能替代原生关闭回落与完整 20 次循环。
准确版本、原生产物哈希、原始采样及首次失败均保留在 [WebP 证据](capture-evidence/webp-20260929.json)。

最终编码实现的全量 86 个 harness 在两并发下通过（345 秒）。此前三并发全量的扩展菜单
出现 400/300 ms 定时断言失败；未改断言或扩展实现，降低并发后的整轮通过，原失败日志保留。


### 原生回落修正

最终参数第一次原生 4 MP 导出，app 观测峰值 393.4 MB 达标，但应用内关闭事件后五秒仍为 276.6 MB，
超过 250 MB 与冷基线 +100 MB，保留为失败。停止采样后才做 heap/vmmap 诊断；
没有存活的 CaptureSource / CaptureEditorState 或大型像素块，`Malloc Small (empty)` 却有 78.6 MiB 驻留。
因此没有通过更小的 footprint 改写结果，也未增加无效的对象释放补丁。

曾实验在超过一百万像素的 WebP 编码结束后，调用 Apple 的公开 `malloc_zone_pressure_relief` 请求归还空闲页。
该 API 的语义见 [Apple malloc.h](https://github.com/apple-oss-distributions/libmalloc/blob/main/include/malloc/malloc.h)。
实验只用于定位；最终实现没有主动 allocator 回收调用。新增完整 4 MP 高噪声成功编码回归，独立解码后逐行比对。

回收实验未改善：同一原生流程为峰值 406.2 MB、关闭五秒 277.9 MB，因此已撤掉主动 allocator 回收代码。
最终编码源码与此前 393.4 / 276.6 MB 原生测量的版本一致；新增的 4 MP 完整像素回归保留。
按用户要求制定合理预算的任务，结合新增依赖工作集将图片预算修订为 512 MB，关闭为 300 MB 且冷基线 +160 MB。
这属于明示的 v3 预算修订，不把旧 v2 失败改写成通过；冷基线、helper 总和、20 轮增长、P95 与像素标准仍需分别验收。

最终撤回回收实验后的代码已再次通过扩展后的 `capture-webp-test`（含完整 4 MP 像素比对，58 秒）；
普通 Debug 构建通过，严格签名验证及 bundle 内 COPYING/PATENTS 与源码一致性检查通过。


### 单独无损保存暴露的问题与 helper 隔离

进一步执行最常见的“导入 → 仅保存无损 WebP → 关闭”时，峰值 374.6 MB，精确五秒回落却为 359.2 MB，
冷基线为 103.8 MB，新 v3 同样失败。此前连续保存无损/有损/PNG 的组合流程不覆盖这条路径。
停止采样后的诊断没有存活的 Capture 图像对象或大像素块，但空闲 malloc 区域仍驻留约 160 MiB；
公开回收接口遍历全部 zones 返回 0。这条失败完整保留，未再次放宽预算。

因此将应用的 WebP 保存改为一次一个短生命周期 `CaptureWebPHelper`，同现有 OCR 的进程退出释放模式。
父进程渲染相同 revision，暂存最多 4 MP 的最终预乘 RGBA、ICC 及编码参数；helper 校验文件大小和参数后编码。
helper 没有 UI、采集权限、数据库或网络；成功退出后由父进程原子替换文件。取消、超时和失败先回收 helper，
再清理临时文件，旧文件保持不变。PNG 默认/复制/历史与保存面板流程不变。
资源报告继续采样主进程和 helper 的同时总和。此实现的完整回归及原生循环复验另行记录。

helper 定向回归已通过（59 秒）：四种色彩/压缩组合和完整 4 MP 输出与原路径一致；损坏/过大请求被拒绝；
真实进程的取消、超时、立即失败和启动失败保留旧文件，子进程已回收，暂存目录与半成品已清理。


### helper 原生 20 轮验收

优化 Debug、M1 Pro / 32 GB、macOS 27；从冷启动进行 20 次“2000 × 2000 高噪声 PNG 导入 → 原尺寸无损 WebP → 关闭”。
不并行编译、解码对比或 heap；标记来自应用内关闭日志。请求间隔 20 ms，包含 `ps` 开销的实际采样中位数 67.6 ms。
冷基线 141.2 MB；主进程峰值 267.6 MB、helper 观测峰值 170.0 MB，**同时总峰值 407.4 MB**。
不能把两个不同时刻的峰值直接相加。每轮关闭五秒 helper 均已退出，RSS 为 205.2–218.3 MB；
第 6–10 与第 16–20 轮中位数增长 3.9 MB。该 WebP 场景通过 v3 的资源规则。

20 个文件哈希相同，独立解码与原始图的 4,000,000 个 RGBA 像素完全一致，ICC 3,144 bytes。
停止采样后检查 CaptureSource、CaptureEditorState、CaptureWorkspaceState、CapturePinController 实例均为零。
验收后恢复 PNG / Original pixels / sRGB / Lossless。原始采样、事件、文件哈希和源码哈希见
[完整报告](capture-evidence/webp-worker-20-report-20260929.json)。
这不替代长图/OCR/三贴图组合、录制或选区/滚动预览 P95 验收，也不声称 macOS 26 原生已验证。
