# Capture 功能与交互实施计划

依据：[Spec](capture-efficiency-spec.md)。日期：2026-10-10。

## M1：本轮实现

- [x] 收敛选区后的范围/模式入口，保留选区前直接选择。
- [x] More Tools 分组菜单，紧凑默认工具，保留已持久化自定义布局。
- [x] 截图现场 Style 菜单，深度调整转入编辑器，输出与关闭入口明确。
- [x] 快速保存与 Save As 分流，目录设置与 settings.json 绑定、备份排除。
- [x] 无覆盖发布、取消清理及私有目录测试。
- [x] 更新功能文档、通过完整测试、Debug 和 lint，记录验证边界。

## M2：原生验收与功能细节

- [ ] 按 Spec 的原生交互清单验收，保存匿名证据及问题；未实测项保持待验收。
- [ ] 按长截图专项矩阵跑真实页面，失败先复现再修复，不宣称与 MacShot 性能相同。
- [ ] 使用用户配置的服务完成 S3/imgbb/Drive 授权与下载比对；无凭证时只验证本地协议。
- [ ] 箭头样式/富文本另立数据和渲染变更，覆盖预览、PNG、历史、撤销及旧文档默认值。

## M3：扩展

- [ ] 以实际需求选择美化预设；不复制 MacShot 的代码或素材。
- [ ] 测试设备对 120fps 的支持、持续录制和资源回收，再决定是否提供高帧率模式。

## 验证记录

2026-10-10，M1 已实现于 dnw/capture-workspace 工作区：

- `./Scripts/run-tests.sh`：102/102 通过，包含新加的 capture-quick-save-test。
- Debug：`xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug -derivedDataPath build/EfficiencyDerivedData CODE_SIGNING_ALLOWED=NO build` 成功；无新增 Swift 警告，保留已有 AppIntents metadata 提示。
- `./Scripts/lint.sh`：通过，现有 66 条警告，无新增。
- Model AppKit/SwiftUI/Cocoa import 检查：无匹配；`git diff --check` 通过。
- 测试中的 PNG 用独立 ImageIO 解码逐像素验证遮挡；文件冲突不覆盖，取消不发布，指定目录失效不创建替代目录。
- Xcode 项目已由 XcodeGen 更新。

原生视觉、菜单交互、焦点恢复与真实服务验收仍待 M2；本轮没有进行同机 MacShot 性能对比，
也没有把自动测试等同于完整原生验收。Debug 为未签名编译检查。随后按用户要求构建签名 Release，并安装到 /Applications/Tinycast.app；
版本号仍为 0.1.0，内容为当前 dnw/capture-workspace 工作区的 M1 实现。
安装时验证新旧 designated requirement 一致、完整 bundle 签名有效，启动进程已确认。
旧应用备份与安装记录保存在 build/install-backups/，此安装不表示 M2/M3 已验收。

2026-10-10，用户截图反馈后的工具栏修正：

- 原生 borderless 菜单把普通菜单和 primary-action 菜单算成不同尺寸；改用共享 SwiftUI 按钮与菜单样式，统一方形单元与图标中心。
- `capture-toolbar-test` 的 45 个原生布局组合通过，涵盖三档尺寸、五种图标和三类控件；完整测试 103/103 通过。
- Debug 编译成功，无新增 Swift 警告；lint 通过，保留已有 66 条警告。
- [匿名原生组件预览](capture-evidence/toolbar-native-20261010.png) 已检查。它来自实际按钮/菜单/图标组件的 NSHostingView 离屏渲染，预览背景和翻译符号为示意，不是完整截图工作区实测。
- 完整工作区的菜单交互、屏幕边缘和焦点恢复仍按 M2 清单验收。
- 签名 Release 构建成功并重新安装到 `/Applications/Tinycast.app`；新旧签名要求一致，完整签名验证通过，进程 51458 启动正常。安装记录：`build/install-backups/efficiency-install-9ae1df3e8e.json`。
