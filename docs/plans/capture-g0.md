# Capture G0 实测记录

日期：2026-09-23。状态：**PNG 数据路径已验证，G0 整体验收未通过。**

2026-09-29 更新：统一 100 MB 门槛已按用户要求替换，当前见 [Spec v3](capture-spec.md#内存和性能-gate)。
下文旧预算的失败与原始测量保留；新预算单独复验，不把旧报告的 failed 改成 passed。

§1–6 是首次基础设施实验的历史快照；原生接入后的当前状态见 §7、§8 和 [验收记录](capture-acceptance.md)。

对应 [Spec](capture-spec.md)、[Plan](capture-plan.md)、[实现说明](../features/capture.md)。

## 1. 环境与证据边界

- Tinycast 基线 HEAD：`5a787533eceb9833e5cba4628433b21f67e97956`，开始时已有 Translation 等未提交改动。
- 当前机器：Apple M1 Pro、32 GiB；实际系统 macOS 27.0（26A428），Xcode 27.0（27A266a），Swift 6.4。
  工程部署目标仍为 macOS 26；本轮没有调整支持范围，也没有获得 macOS 26 的运行证据。
- 两个屏幕的 AppKit frame 为 `(0,0,1728,1117)`、`(-1920,37,1920,1080)`，backingScaleFactor 均为 2。
  本轮 5K 样本由像素函数生成，不能写成实际 5K 屏幕捕获通过。
- 当前工具宿主的 `CGPreflightScreenCaptureAccess()` 返回 true；这不证明 Tinycast Dev 自身已有 TCC 授权。
- 已运行的 Dev 来自另一个 worktree，不作为当前 checkout 的 idle/peak 基线；本轮未重启它。
- 原始本地日志：`/tmp/tinycast-capture-g0.GAwt0S/`。下方结果和仓库内 harness 用于长期复现。

所有样本为程序生成的 sRGB RGBA8 数据，不读取桌面或用户文件。剪贴板使用 `NSPasteboard.withUniqueName()`，
验证结束释放；不读写系统剪贴板，也未测试 Finder、Preview 或其他应用中的粘贴。

## 2. PNG 与文件分块

比较对象使用同一组确定性像素。ImageIO 候选通过带 `getBytesAtPosition` 回调的 `CGDataProvider` 按需提供原图；
没有预先分配整图。新路径先逐行写入最大 1024² 的文件块，再用系统 zlib 逐行输出 PNG。
每项均为单次实测，时间不是 P95。MB 为十进制 `bytes / 1,000,000`。

| 路径/样本 | 输出 PNG | 最大 RSS | peak memory footprint | 结果 |
| --- | ---: | ---: | ---: | --- |
| ImageIO + provider，1600 × 30000，含私有 pasteboard 往返 | 1,534,529 bytes | 213.07 MB | 199.87 MB | 原尺寸成功，但单独进程已超 100 MB |
| 文件分块 + 逐行 PNG，同一长图，含私有 pasteboard 往返 | 301,393 bytes | 17.60 MB | 4.36 MB | 写块 1.25 s，编码 1.34 s |
| 文件分块 + 逐行 PNG，5120 × 2880，含私有 pasteboard 往返 | 75,497 bytes | 17.27 MB | 4.23 MB | 写块 0.29 s，编码 0.31 s |
| 高熵 RGB 长图 1600 × 30000，只写文件 | 164,850,169 bytes | 9.16 MB | 3.42 MB | 写块 1.30 s，编码 8.81 s；内存未随文件长度增长 |
| 上一高熵 PNG，只写私有 pasteboard、不读取返回数据 | 164,850,169 bytes | 508.00 MB | 332.78 MB | API 成功，但严重超预算 |

标准长图与高熵长图分别在独立解码进程中通过 ImageIO 解码到明确的 RGBA context，
逐字节检查全部 48,000,000 像素，结果一致。解码验证进程会分配整图，**没有把它的内存计为低内存输出路径**。
不同 PNG 文件大小来自编码/过滤方式，原始尺寸和像素保持相同。

由此选择：PNG 使用 `CapturePNGWriter` 的系统 zlib 流式实现，复用现有 `Zlib.crc32`；不增加媒体 helper。
淘汰将整张长图交给 ImageIO 的候选。是否需要捕获/OCR helper 仍待组合测量，不能从这组数据推断。

## 3. 剪贴板决策尚未关闭

301 KB、75 KB 的 PNG 私有剪贴板往返成功，只证明这些已压缩小文件能交付。
`.mappedIfSafe` 不能保证大 PNG 的 pasteboard 写入有界，165 MB 高熵样本即使不读回也达到约 508 MB RSS。

接入生产复制前必须做两件事：

1. 根据已编码文件大小和当前整款应用内存余量预检；超预算时保留结果，明确提供保存文件路径，不默默缩小分辨率。
2. 对可复制范围验证真实接收应用、关闭编辑器后的可用性、历史单次接收和重复操作回落。

这属于 Spec 已有的资源上限保护；具体数值须经真实 app 测量后确定。本轮没有落一个猜测的 8/16 MB 阈值，
也没有把文件 URL 写入当成完整 PNG 剪贴板交付。

## 4. 已落代码与工程检查

- `CapturePixelSize` / `CaptureRaster`：尺寸验证、tile 网格、尾块尺寸、受限 manifest 解码。
- `CaptureRasterStore` / `CaptureRasterReader`：逐行写块、完整目录发布、有限文件描述符、反向读取、损坏/符号链接拒绝。
- `CapturePNGWriter`：完整原尺寸、sRGB 和 straight alpha、取消检查、临时输出、成功后原子替换。
- `CaptureViewportPolicy`：普通图适合窗口，纵向长图适合宽度，横向长图适合高度；尚未接入原生 UI。
- `capture-raster-test`：跨块/跨带、全部输出像素、透明像素、1px 窄图、取消后保留旧输出、损坏文件等定向检查通过。

XcodeGen 已将这些源文件纳入工程。开始快照的生成工程使用本机临时签名；重新生成后恢复 `project.yml` 中的
`Tinycast Self-Signed`，本机没有该证书，默认构建因此失败。使用与开始快照相同的本地临时签名完成 Debug 编译：

```sh
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY=- build
```

编译成功，无新增 Swift warning；与基线相同的 AppIntents metadata extraction skipped 提示仍存在。
完整 suite 最终 78/78 通过（55 s）；首次并发运行 `clipboard-text-test` 有计时超时，单独运行（5.1 s）和完整重跑均通过。
该 harness 及其 Clipboard 源文件没有改动；记录这次时序敏感性，不将首次失败隐藏为全程无故障。
`./Scripts/lint.sh` 通过，无新增 lint warning；Model import 纯度检查通过。
没有改发布签名、创建证书或授予系统权限。正式原生运行应按仓库 signing.md 的稳定身份流程完成。

## 5. 来源清单

Macshot 参考 HEAD：`a93bf38`；仓库 LICENSE 文件为 GPL version 3 文本。

| 参考文件 | 本轮处理 |
| --- | --- |
| `macshot/Capture/ScrollFrameAnalyzer.swift` | 仅作后续配准分析入口，未移入代码 |
| `macshot/Capture/ScrollCaptureController.swift` | 仅作后续流程参考，未移入代码 |
| `macshot/UI/Tools/AnnotationToolHandler.swift` | 未移入代码 |
| `macshot/Model/Annotation.swift` | 未移入代码 |
| `macshot/Services/HistoryStorage.swift` | 未移入代码 |

当前新增 Swift 为本仓库新写实现，仅调用系统框架、系统 zlib 和已有 checksum 工具。
因此本轮没有可登记到 NOTICE 的 Macshot 代码拷贝；以后若复制具体代码，仍须记录来源并保留原许可信息。

## 6. 复现与下一关

性能命令见 [testing.md](../testing.md#capture-raster-benchmark)。ImageIO 基线可单独编译：

```sh
capture_probe=$(mktemp -d /tmp/tinycast-imageio.XXXXXX)
swiftc -swift-version 6 -O Tinycast/Features/Capture/Model/*.swift \
  Tests/capture-imageio-performance.swift -o "$capture_probe/imageio-bench"
/usr/bin/time -l "$capture_probe/imageio-bench" 1600 30000 "$capture_probe/output.png" pasteboard
```

下一关是正确签名和 TCC 身份下的真实捕获：SCScreenshotManager 区域/窗口、混合 DPI、焦点/菜单保留、
页面滚动透传、自动滚动目标约束，以及真实 app 的基线 + 候选帧 + 预览 + 输出总预算。
三个贴图 + OCR、20 次打开关闭和 5 秒回落尚未执行；实时拼接、窗口控制和编辑器尚未实现。
G0、G1 和一期均保持未完成，不用本轮数据路径验证替代长截图产品验收。

## 7. 原生接入后的更新

目前已实现捕获会话、滚动配准、编辑、历史、贴图、共享 OCR 和 Translation；不再处于只有存储基础的阶段。
PNG 的早期实验结论保持。复制曾接入 `resident + 4 × encoded + 4 MB < 100 MB` 和 8 MB 编码大小的保护；
原生基线已超标使普通小图也无法复制。本轮删除动作级 RSS 拒绝，只保留 8 MB 编码上限，恢复普通复制路径。
这不代表整款 app 通过内存验收，亦未改变 G0 的 100 MB 目标。

前轮原生 Dev 冷启动 RSS 约 109 MB、交互后约 165 MB，已超出绝对门槛；原尺寸保存仍可完成。
用户已授权 Dev 的屏幕录制与辅助功能，真实 SCK 选区已运行；自动滚动和复制接收仍未验收。
自动化通过不关闭内存失败项。完整数字与实际图片/译文证据、系统状态及
剩余验收矩阵，统一记录于 [当前验收](capture-acceptance.md)。

## 8. 2026-09-28 工作区性能续测

新入口的 Debug 延迟有一处已定位的 CPU 热点：Swift 逐像素预乘/去预乘循环。
已改为系统 Accelerate 的 vImage 原地转换，并以半透明/不透明/透明像素往返验证。
冻结底图预览改为直接从已有 CGImage 缩小一次，避免为未编辑底图重复读取、绘制全部 tiles。

3456 × 2234 的合成图单次样本：Debug 的写入 + 文档预览由 4.49 s 降至 0.35 s；
同一独立进程的最大 RSS 仍约 82.4 MB。样本和配置见
[结构化证据](capture-evidence/workspace-performance-20260928.json)，仓库 benchmark 增加 `source` 模式复现。
这不是热键到选区的 P95，也没有把独立进程结果计作整款应用通过。

当前 checkout 的冷启动采样：Debug RSS 106.43 MB，保持 Dev 身份的 `-O` 构建 RSS 102.69 MB，
都已在进行原生操作前超过绝对 100 MB 门槛。`vmmap` 的 physical footprint 与 RSS 分开记录，
不通过替换口径关闭失败项。`Capture Prepare` signpost 覆盖目标获取、屏幕采集、写入与工作区创建；
`Scripts/build-and-run.sh --profile` 用相同 bundle ID、签名与数据目录生成优化构建，便于后续对照。

G0 仍为失败：缺同版本原生全链路 P95、20 次循环及 5 秒回落、三贴图/OCR 同时存活的总 RSS，
以及超过基线部分的分配归因。新增性能优化不改变 spec 的预算，也不关闭长图新入口验收。

### 2026-09-29 人物候选 helper 续测

真实 UI 执行 Find People → 应用 → Copy → Close。主进程为本 checkout 的 PID 66858，
只统计该进程及其直属 TextRecognitionHelper，未将其他 worktree 的 Dev 算入。
目标每 200 ms 采集 `ps`，90 秒取得 343 次样本：主进程峰值 223,215,616 bytes，helper 峰值
25,542,656 bytes，同一采样时刻最大总和 241,434,624 bytes。
关闭后 5.016 秒 RSS 为 203,538,432 bytes，helper 为零；本轮开始的热基线为 207,585,280 bytes。
单轮回落通过热基线比较，100 MB 绝对标准仍失败。采样峰值不排除两个采样点间存在更高瞬时峰值。
证据在 `workspace-native-20260928.json` 的 `peopleCovers.memory`，原始样本保存在
`/tmp/tinycast-completion-2_njcdaj/people-memory.json`。


### 2026-09-29 普通截图 20 次循环

使用本 checkout 的 Debug PID 74664，每轮从原生 palette 执行 Capture Screenshot，拖选 1000 × 500，
复制后关闭工作区。20 轮均显示复制成功；20 个独立 PNG 的 IHDR、全部 chunk CRC、解压长度与行过滤值有效。
采样间隔 200 ms，过程中没有运行构建、harness、heap 或调试器。

冷启动主进程 RSS 110,657,536 bytes，峰值 268,468,224 bytes，无 helper；
最后一轮关闭 5.022 秒为 196,231,168 bytes，继续空闲后为 194,641,920 bytes。
第 10–20 轮关闭后的驻留约 194–196 MB，没有逐轮增加同等图像大小，但冷基线 +5 MB 和绝对 100 MB 均失败。
这仅覆盖普通截图，不能代替长图、OCR、录像的循环及入口 P95。
证据见 `workspace-native-20260928.json` 的 `ordinaryCaptureCycles`，原始采样及输出清单位于
`/tmp/tinycast-completion-2_njcdaj/capture-cycles-{memory,outputs,analysis}.json`。

另一个已结束的诊断进程中，调用公开的 malloc_zone_pressure_relief(NULL, 0) 返回释放 0 bytes；
调试器附加本身明显改变 RSS，因此该进程的后续数值不用于正常基线，也未把手动 pressure relief 加入生产路径。
