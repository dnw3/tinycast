# 磁盘清理实施 Plan

对应 [Spec](cleanup-spec.md)。在 `dnw/cleanup` 分支开发，每期完成后再合回 `main`。

## 实施顺序

### 第一期：核心清理

- [x] 调研：Purge 的源码、清理清单、删除引擎和事故记录；横向对比 Mole、CleanMyMac、Lemon、Pearcleaner；
      梳理 Tinycast 的全部接入点；对照 AGENTS.md 审查方案。
- [ ] 0 测量（Release 24.6 MB、整轮扫描探针峰值 59 MB 已记录；隐私框与应用内常驻内存待原生验收）：在 Dev 版关闭完全磁盘访问权限，访问容器、组容器、`.Trash`、Messages 预览、Safari 缓存时，记录是否弹出系统隐私框。
      同时记录 Release 包大小、冷启动常驻内存、一次扫描后的内存占用，作为基线。
- [x] 1 纯模型和 `cleanup-test`：`CleanupTarget`、`CleanupCatalog`、`CleanupSafetyPolicy`、`CleanupPlan`、
      `KeepNewestPolicy`、`CleanupReport`；同时写 `NOTICE.md` 和 `docs/features/cleanup.md`。
- [x] 2 副作用层和 `cleanup-walk-test`：`CleanupAccess`、`DiskUsageScanner`、`CleanupScanner`、`CleanupRunner`。
- [x] 3 palette 外壳：新增 `PaletteScreen.isPrimaryActionDestructive(at:)`，行为保持不变；新增 `navigateHorizontally(_:at:)`。
- [x] 4 第一个用户可见的版本：`CleanupSession`、文案本地化、`CleanupCoordinator`、`CleanupScreen`（主屏和明细）、
      `CleanupList`、`CleanupDetail`、设置页；命令、设置页、settings.json 的 `cleanup.commands`；`UpdateReadiness` 增加 `.cleaning`。
- [x] 5 偏好设置：`CleanupSettingsStore` 存删除方式和排除列表，两者都不进备份；新增 settings.json 键；⌘K 增加「不再扫描此项」。
- [x] 6 快速清理命令；废纸篓行和清空废纸篓。
- [x] 7 概览行、容量条、新增 Theme 令牌、无障碍标签；记录实测数字，更新 fork-maintenance。

### 第二期：深度清理

- [x] 工具命令（每条先确认不需要管理员权限）：simctl、docker、brew、pnpm、go、tmutil。
      外部命令复用 `ToolRunner` 和 `ExecutableLocator`。
- [x] 闲置项目：规则目录、活动判定、进程工作目录、`git ls-files` 保护。（`CACHEDIR.TAG` 通用规则尚未做）
- [x] 文件：大文件、重复文件、安装包、未完成的下载、macOS 安装器、AI 模型、虚拟机、iOS 备份。
- [x] iCloud 本地副本：先实测 `evictUbiquitousItem` 能不能用，再决定收不收。
- [x] 残留：按代码签名和 App Group 判定归属；失效的启动项。
- [x] 系统更新残留：实测 osascript 管理员授权弹窗；判定条件（无待装更新、早于安装时间、跳过 `Locked Files`）放在纯模型并由 harness 锁定。
- [x] 旧扩展版本（以 `.obsolete` 为准）和旧 CLI 版本；维护小工具。

### 第三期：磁盘空间分析

- [x] `.diskUsage`：逐层聚合，每层只保留有限的前 N 项。如果内存持续上涨，改用辅助进程。

### 第四期：自动化

- [x] 定时清理：`CleanupSchedule` 加 `CleanupScheduleStore`；只能在 App 里开启，开启前确认，不进备份。
- [x] 空间不足提醒：HUD 加菜单栏菜单行。
- [x] 清理历史。

## 约束

- 每一步都要通过：完整 run-tests、Debug 构建无新增警告、lint、Model 纯度检查、`xcodegen generate` 后工程文件一致，
  文档在同一步里更新。
- 提交、合并、推送都先征得用户同意。
- 不改上游的 `AppSettings.swift`。File Search 的私有视图需要用时复制一份，并在 fork-maintenance 里记录。
- 不新增 singleton、actor 或第三方依赖；不改 `EdgeDissolve` 和 `ThinScrollbar`。
- 移植 Purge 的规则时同时吸取它的事故教训，不照搬它的多行注释，改写进功能文档的审计表。
- Mole 是 GPL-3.0，只参考它的路径和规则事实，不复制代码。

## 验证记录

### 2026-10-17 调研期测量

本机：macOS 27.0（Darwin 27.0.0），终端没有完全磁盘访问权限。下面数字是一个 `-O` 编译的独立
`getattrlistbulk` 遍历原型测出来的，按 inode 对硬链接去重：

| 范围 | 结果 |
| --- | --- |
| 主目录（16.5 万文件、2.6 万目录，10.27 GB） | 2.56–3.18 s，峰值常驻内存 6.3 MB |
| `/Applications`（14.2 万文件） | 1.00 s，6.3 MB |
| `du -sk ~` 对照 | 3.61 s，5.4 MB |
| 第一次遍历 `~/Library` | 107 s。很可能是没有完全磁盘访问权限时碰到了受保护目录，触发了系统隐私弹窗。之后再遍历主目录只要约 3 s |

结论：

- 在主进程内计算大小是可行的，不需要辅助进程。
- 没有完全磁盘访问权限时，扫描器必须完全不碰受保护目录。
