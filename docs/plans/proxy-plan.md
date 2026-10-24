# 代理实施 Plan

对应 [Spec](proxy-spec.md) · [设计稿 v3](proxy-redesign/index.html)（[v2 原型](proxy-prototype/index.html)只作历史参考）。
在 `dnw/proxy` 分支开发，提交、合并、推送都先征得用户同意。

## 交付原则

- 先做不碰系统网络的部分。纯模型、用户态内核和界面都可以在 Clash Verge Rev 运行时开发验证：内核用独立端口，
  不修改任何系统设置。
- TUN 的原生验收会中断当前网络（两个 TUN 不能共存，需要先退出 Clash Verge Rev），只在用户在场时进行。
- 每期结束都要通过：`./Scripts/run-tests.sh`、`./Scripts/lint.sh`、Debug 构建无新增警告、Model 纯度检查、
  `xcodegen generate` 后工程文件一致；文档在同一步更新。

## 阶段

### P0 可行性

- [x] 内核选型：mihomo 与 sing-box 的协议、接口、维护与性能对比，见下方验证记录。
- [x] 核实 mihomo 行为：provider 先按 YAML 解析、失败后按分享链接解析；同名节点按名称选择；空 `use`
      组的报错与 `COMPATIBLE` 占位；`regexp2.MustCompile` 对非法组筛选会崩溃；`PUT /configs` 不重建控制接口；
      Unix 控制接口不校验 secret 并把 socket 设为 0666。
- [ ] 最小 TUN 助手原型：管理员授权安装传统 LaunchDaemon；自签名下 `setCodeSigningRequirement` 拒绝其他进程；
      经 XPC 传递已连接的 socket fd。
- [ ] root 内核以生成的配置开启 TUN，核对分流、DNS 劫持和 DNS 占位还原（需要用户在场，先退出 Clash Verge Rev）。
- [ ] 内存基线：Tinycast 空闲、用户态内核空闲、助手内核空闲与 100 MB 下载期间。

### P1 纯模型与配置生成（2026-10-22 完成）

- [x] `ProxyJSON`：确定性 JSON 值与编码。
- [x] `ProxyRegion`：地区表与名称归类，正则同时兼容 ICU 与 Go regexp2；地区代码只按大写匹配。
- [x] `ProxySource`、`ProxyStrategy`、`ProxyRoute`（内置分类与规则集）、`ProxyUserRule`、`ProxyTarget`、
      `ProxyGeneral`、`ProxyProfile`（方案工厂，当前方案由内置分流反推）、`ProxyProblem`（重名、保留名、
      不安全字符、悬空引用、成员成环、非法正则与反引号、非法规则值、DNS 与端口）。
- [x] `ProxyRuleMatch`：「我的规则」测试用的纯函数匹配。
- [x] `ProxyConfigBuilder`：providers、策略组、分流组、规则集、规则、DNS、TUN；同时返回要复制进内核目录的本地文件、
      加载后要重设的选择，以及缺少链接而跳过的订阅。
- [x] `Tests/proxy-test.swift`（198 项断言），登记到 `run-tests.sh` 与 `docs/testing.md`。
- [x] 用真实内核校验生成的配置：官方 v1.19.32 发布包的 `-t`，以及本机回环端到端运行（见验证记录）。

### P2 内核与控制接口（用户态，2026-10-22 完成）

- [x] `Vendor/mihomo/`：`core.env` 是版本与各架构 SHA-256 的唯一出处，同目录有许可与说明。`Scripts/fetch-mihomo.sh`
      下载、校验并解压到 `build/vendor/mihomo/`，保留压缩包；构建阶段「Embed mihomo」复制到 `Contents/Helpers/mihomo`
      并签名。没有内核时报告「缺少内核」。
- [x] `Scripts/upgrade-mihomo.sh`：一条命令升级打包内核。按 GitHub 公布的 SHA-256 校验两个架构的压缩包，`-v` 核对，
      比对 LICENSE，改写 `core.env` 与 `NOTICE.md`，跑 smoke；失败全部还原。`--check` 只报告最新版本。
- [x] `ProxyHTTP`（Model）：请求编码，响应解析（Content-Length、chunked、按行流），由 harness 覆盖。
- [x] `ProxySocket`、`ProxyAPIService`（Service）：Unix socket 上的单次请求与流式订阅；取消即中断读写，带超时，
      预先检查 socket 路径长度。
- [x] 控制接口数据模型 `ProxyAPI`、`ProxySnapshot`：`/proxies`、`/providers/proxies`（订阅信息）、`/traffic`、测速结果。
- [x] `ProxyCoreRunner`：`-t` 在临时目录运行（它会写 `cache.db`），取出内核的第一条报错或 panic；`-v` 识别版本与架构；
      启动用户态内核并写日志。
- [x] `ProxyStore`：`profile.json` 原子读写，损坏时留存副本；钥匙串中的订阅链接。
- [x] `ProxyManager`（`@MainActor @Observable`）：原计划的 `ProxySession`。它负责内核的生命周期和策略，按命名表应叫
      Manager。连接状态、节点与延迟、订阅信息、分流选择；`reloadKey` 决定只改选择还是重载配置；内核崩溃后按退避重启；
      由 `AppCore` 持有并在 `start()` 接线。
- [x] 内核更新（D8）：`ProxyCoreRelease`、`ProxyCore`（Model）解析发布信息、决定运行哪个内核；`ProxyCoreDownloader`、
      `ProxyCoreInstaller`（Service）下载、校验、安装；`ProxyManager` 检查更新、安装、换内核与回退、恢复内置版本。
- [x] harness：`proxy-api-test`（HTTP、负载、快照、重启策略、`-t` 输出、发布信息、内核选择）；`proxy-service-test`
      （进程内假控制接口、存储与钥匙串、用假内核脚本测安装器）。
- [x] `Scripts/proxy-smoke.sh`：把 P1 的本机回环端到端检查固化进仓库，并覆盖应用内安装、回退与恢复内置版本。

### P3 TUN 助手（2026-10-23 完成；助手卸载后无残留一项待用户输入管理员密码）

- [x] `TinycastProxyHelper` 工具目标（project.yml，构建阶段「Embed TUN helper」以 `<bundle id>.proxy-helper`
      签名），XPC 协议与版本（`ProxyHelperWire`）。
- [x] 安装、卸载脚本与 `osascript` 授权；校验过的 root 副本用自己的签名身份写 `grant.json`（Tinycast 只传 uid）。
- [x] 内核副本复制、校验、原子替换；启动、停止、崩溃退避重启；期望状态与 DNS 备份存在 `record.json`。
- [x] `installCore`：打包内核校验签名与哈希；下载的内核只在下载校验的同一次运行里，用内存中算出的哈希交给助手，
      没有就改用打包内核。TUN 模式下的内核更新、回退和恢复内置版本都经助手。
- [x] `openController()` 交出 fd；DNS 占位与还原。
- [x] `verify-signature.sh`、`release-fork.sh` 覆盖新的助手与内核；硬化运行时；`release-fork.sh` 先运行
      `fetch-mihomo.sh`，打包的必须是 `core.env` 锁定的版本。
- [x] 设置 › 代理 › 通用：TUN 一组（TUN 模式、助手的安装／更新／卸载、DNS 占位）与「退出 Tinycast 后保持连接」；
      状态卡第三栏在助手运行内核时显示 TUN。
- [x] 原生验收（用户在场，先退出 Clash Verge Rev）：安装助手，AC-1、AC-6、AC-7（root 内核被杀后的恢复只由
      harness 覆盖，本机杀 root 进程需要管理员权限）。
- [ ] 卸载助手后无残留（需要管理员密码）。

### 界面复查（2026-10-23，用户提出三点后整体截图复查）

- [x] 未装好助手时「TUN 模式」显示为关并置灰，副标题提示先安装或更新；「DNS 占位」跟着置灰。
- [x] 导入本地文件的面板挂成设置窗口的表单，跟着窗口进全屏空间（原先用协作式 `NSApp.activate()` 加 `runModal`，
      面板会开到别的桌面）。
- [x] 来源只贡献节点要讲清楚（用户选「只用节点，讲清楚」）：导入 HUD、来源编辑器的「文件内容」、节点文件编辑器底部、
      来源一节的说明；`ProxyNodeFileOutline` 按顶层键逐行计数代理组、规则、规则集、代理集和其他设置。
- [x] 节点页「查看节点…」：按地区分组、可搜索、可按来源筛选，显示协议、UDP 和延迟；来源右键菜单也能打开。
- [x] 台湾不显示旗帜（中国大陆地区下画成缺字方框），匹配仍认旗帜。
- [x] TUN 下「显示日志…」：订阅 `/logs?level=warning` 写入 `Proxy/Core/tun-core.log`，打开最近写过的日志；不改助手协议，
      不必重装助手。
- [x] 分流页的规则集状态（`/providers/rules`）与「立即更新」（`PUT /providers/rules/{name}`）。
- [x] 启动器：延迟不再被长节点名挤掉；策略选项的详情副标题是「策略 · 类型」，⌘K 首项是「使用此选项」；
      状态卡两侧短栏按内容收窄（最小宽度），长节点名字号与其他栏一致；分流子屏只显示策略和延迟，不再每行重复节点名；
      「域名关键词」改用不随语言变化的图标。
- [x] 设置：来源编辑器字段等宽对齐；占位提示加「例如」；规则集链接占位不再是蓝色链接样式；规则测试的行标签改为
      「域名或 IP」；url-test 类型改叫「自动选择」，不再和「自动最快」重名；策略页给手动策略加节点菜单（按地区分子菜单）；
      地区按钮下说明「一个都不选表示全部地区」。
- [x] 接回退出时保留的 TUN 内核时，「已连接」显示内核真正的启动时间，不是接回的时间。

### P4 启动器（2026-10-22 完成，界面目视待用户在场时验收）

- [x] `CommandID` 与 `SettingsTab.ownedCommands`：选择节点、分流、策略、添加分流规则、连接代理、断开代理、
      节点测速、更新订阅。连接与断开是两条命令：按 `wantsConnection` 只列出适用的一条（命令名不能随状态改写），
      热键两条都能用。代理关闭时全部隐藏。
- [x] 状态卡与首次使用引导：`LauncherScreen` 的结果卡多一种（`ProxyLauncherCard`），三栏为默认策略当前节点与延迟、
      分流方案、连接状态与混合端口（P3 后换成 TUN）。没有来源时是引导，剪贴板里像订阅的链接回车即添加并连接。
- [x] 分流、策略、节点子屏与 ⌘K；节点按地区分段、模糊搜索，右侧详情写明来源、协议、选中后影响的分流。
      未连接时第一行是「连接」。策略子屏有三种进入方式：浏览、给分流挑、给新规则挑。
- [x] 「添加分流规则」：原型是三栏表单加 ⌘↵。实现改为与「分流 → 策略」相同的两步列表——输入框就是网站
      （`ProxyBrowserPage` 经 Apple Events 读 Safari 与 Chromium 系浏览器前台页面，2 秒超时，读不到就留空），
      下面列出匹配方式，回车进入策略列表，回车保存。全程键盘、和其他子屏一致，也不用改上游的原生编辑器管线
      （`isNativeEditor` 与 `PaletteWindowController` 的 ⌘↵ 分派）。
- [x] HUD：切换结果、测速进度（全部测速可取消）、更新失败；原型 ⌘K 里的「临时全局代理」也已实现（不保存）。
- 未做：原型节点详情里的「实时流量」和「最近 10 次平均延迟」（内核只按全局给流量，按节点要聚合 `/connections`）。

### P5 设置与编辑器（2026-10-22 完成，界面目视待用户在场时验收）

- [x] `SettingsTab.proxy` 与四页分段；`SettingsSearchCatalog` 条目，搜索结果先切到所在的页。
- [x] 编辑策略（实时预览匹配的节点）、我的规则（排序用菜单上移下移，未做拖动；测试命中）、编辑订阅、
      本地文件（导入原位文件或新建；保存后内核经 `PUT /providers/proxies` 重读，读不了时提示带上内核给出的原因）、
      自定义规则集、生成的配置预览。
- [x] 删除来源、删除策略、恢复默认设置的对话框；跨来源重名提示与一键前缀。安装和卸载助手的对话框在 P3 完成。
- [x] 通用 › 内核：版本与来源、检查更新、下载进度与取消、恢复内置版本（`ProxyManager.coreUpdate`），
      失败原因的本地化文案。
- [x] 订阅更新间隔与「经代理更新」从每个来源移到通用设置（与原型一致），旧文件缺的键按默认值解码。
- 未做：「配置覆写」与覆写脚本（等用户需要时单独设计）。TUN 一组在 P3 完成。

### P6 收尾

- [ ] 安装包内的规则快照；首次使用不必先访问 GitHub。
- [ ] `docs/features/proxy.md`（不变量）、`NOTICE.md`（mihomo GPL-3.0 与源码链接）、`fork-maintenance.md`。
- [ ] 简体中文本地化与 `localization-test`。
- [ ] 资源验收 AC-8，完整原生验收矩阵。

### v3 重新设计（2026-10-24 用户确认方向：D9–D14）

用户认为原界面不直观、不美观。设计稿 v3 把状态放在最前，三层画成流向图，管理搬进代理窗口，设置只留偏好。
用户确认：独立窗口、三种模式取代方案、活动页首批做、菜单栏图标默认关闭；另要求多补地区，并问内置分流能否订阅
（分析见验证记录 2026-10-24，结论为 D13）。

- [x] 写代码前先 rebase 到 `origin/main`（用户要求）。2026-10-24：分支没有自己的提交，工作区备份后快进到 v1.4.1
      （`afb2948e`）再放回改动。冲突在 `AppCore`、`LauncherScreen`、`SettingsTab`、`Localizable.xcstrings`、
      `docs/testing.md` 和工程文件：工程由 `xcodegen generate` 重新生成，本地化表在上游版本上加入代理的 479 个键。
      上游把设置组件的文字参数改为 `LocalizedStringResource`，代理编辑器的标题随之改写。上游现在发 8 种语言，
      `lint.sh` 检查每个字符串都有译文：代理的文字在 R4 定稿后统一翻译。

#### R1 模型与服务

- [x] `ProxyMode`（规则、全局、直连）存在 `profile.json` 的文档层，与 `connected` 并列，旧文件缺键时为规则。
      `ProxyManager.mode` 取代 `isGlobal`；配置写入当前模式而 `reloadKey` 不含它，切换只发 `PATCH /configs`；
      `GLOBAL` 组固定选默认策略。
- [x] 地区表扩充到 79 个（D14）：简繁中文、英文、城市、ISO 代码和常见机场代码。处理前缀冲突（印度与印度尼西亚、
      罗马与罗马尼亚、蒙古与内蒙古）；中国大陆只认「回国」「中国大陆」等词，不认 `CN`（会误中 CN2 线路）。
- [x] 规则库 `ProxyRuleCatalog`（D13）：常用服务与类别 86 项（9 组），各有规则集、图标和中英文检索词；
      `ProxyRouteCategory` 增加对应的 case（旧值不变）。任意 geosite、geoip 名称的分流用 `.custom` 加 `.catalog` 位置。
- [x] 规则集链接识别 `ProxyRuleSetDetection`：按内容判断格式（zstd 魔数为 mrs，`payload:` 为 YAML，否则为文本）
      与类型（规则前缀为混合，全是地址段为 ipcidr，否则为域名），mrs 的类型按路径判断，可以改。
- [x] `ProxyFlow`：流向图的纯数据（左列行、按目标分组、策略与出口、全局与直连下的汇聚）。
- [x] 内核接口：流式 `/traffic`、`/connections` 快照、`DELETE /connections/{id}`；`ProxyTrafficMonitor`、
      `ProxyConnectionsMonitor` 只在窗口打开、页面可见时运行。
- [x] 菜单栏偏好放在 `ProxyGeneral`（默认关，可选显示网速），与其余代理设置一样不进设置文件。
- [x] harness：地区命名、模式编码与配置、规则库、链接识别（Loyalsoldier、blackmatrix7、SukkaW、meta-rules-dat 的样本）、
      流向数据、`/traffic` 与 `/connections` 解码。

#### R2 代理窗口

- [x] `ProxyWindowState`、`ProxyWindowRootView`（`NavigationSplitView`，桥接工具栏与标题）、`ProxyWindowChrome`、
      `ProxyCoordinator.showWindow(_:)`；编辑面板用 `SettingsEditorPresenter` 挂在代理窗口上。
- [x] 概览：出口卡、流量卡、流向图、状态卡；没有来源时为三步引导。
- [x] 节点：策略标签、说明行（类型、当前出口、用于哪些分流）、节点卡片（手动策略点选即切换）、全部节点
      （按来源筛选）；新建、编辑策略。
- [x] 分流：网址测试（经混合端口发起一次连接，从内核 info 日志流读出命中的规则与出口后断开）、我的规则、按类别
      （拖动排序、行尾开关、目标菜单）、其他流量、规则集状态、恢复推荐分流；添加分流面板（规则库搜索、
      geosite 与 geoip 名称、从链接添加）。
- [x] 订阅：只用节点的说明、订阅卡片（用量、到期、启用、更新、编辑、查看节点）、本地文件卡片、添加卡片。
- [x] 活动：连接列表（筛选、搜索）、为连接添加规则。

#### R3 菜单栏、启动器、设置

- [x] `ProxyMenuBarController`：`NSStatusItem` 加 `NSMenu`，每次打开时按当前状态重建；图标随连接状态，可选网速。
- [x] 启动器：状态卡三栏为出口、模式、连接；新命令「打开代理窗口」和三种模式；「代理分流」「代理策略」改为打开
      窗口对应页面，去掉分流子屏和只用于浏览的策略子屏。
- [x] 设置 › 代理只留偏好；搜索条目指向窗口页面；`ProxyEditRequest` 改为发给窗口。
- [x] 延迟着色阈值改为 150 ms。

#### R4 收尾

- [x] 一句话一个字面量，计数用复数变体；8 种语言的译文（`sync-strings.sh`、`check-localizations.js`）。
- [x] `docs/features/proxy.md`、`docs/ui.md` 的代理窗口一节、`docs/testing.md`、`fork-maintenance.md` 的上游改动清单。
- [x] 全量 harness、lint、Debug 构建无新增警告、Model 纯度；签名 Release 安装后原生验收窗口五页、菜单栏、启动器、
      设置与首次使用（不中断用户网络）。全部通过后再提交。

## 约束

- 新依赖只有 mihomo 二进制（D1、D6）。版本与校验和只写在 `Vendor/mihomo/core.env`，许可与说明在同目录；不引入 Go 工具链、
  Swift 包或 YAML 库。
- 尽量少动上游文件，动过的逐一记入 fork-maintenance：预计有 `AppCore`、`CommandID`、`CommandCatalog`、
  `SettingsTab`、`SettingsAnchor`、`SettingsSearchCatalog`、`SettingsDetailView`、`KeychainSecretStore`、
  `project.yml`、`Scripts/run-tests.sh`、`Scripts/verify-signature.sh`、`Scripts/release-fork.sh`。到 P5 为止已动
  `AppCore`、`CommandID`、`CommandCatalog`、`LauncherCoordinator`、`LauncherScreen`、`LauncherList`、`PaletteMode`、
  `RootPaletteView`、`SettingsTab`、`SettingsAnchor`、`SettingsSearchCatalog`、`SettingsDetailView`、
  `KeychainSecretStore`、`Localizable.xcstrings`、`NOTICE.md`、`project.yml`、`Scripts/run-tests.sh`，
  以及 `docs/testing.md`、`docs/development.md`、`docs/fork-maintenance.md`（「我们保留的改动」表的 Proxy 一行）；
  P3 又动了 `Scripts/verify-signature.sh` 和 `docs/signing.md`，`Scripts/release-fork.sh` 是 fork 自己的脚本；
  界面复查给 `SettingsCoordinator` 加了 `runSheet`（导入面板挂在设置窗口上）。
  复用而不修改的有 `AppVersion`、`ReleaseArchitecture`（Updates/Model）、`Platform/Compression/Zlib`、
  `ProcessExit`、`AppPaths`、`FuzzyMatch`：上游改了它们的接口，同步时代理会编译失败。
- 不新增 singleton 或 actor；`Features/Proxy/Model/` 只用 Foundation（校验摘要另用 CryptoKit，与
  `SettingsFileIdentity` 相同），环境事实全部作为参数传入。
- 不改 `EdgeDissolve` 和 `ThinScrollbar`。
- 内核与助手都是独立进程，按需启动；Tinycast 主进程不加载 Go 代码。

## 验证记录

### 2026-10-21 内核选型测量

本机 macOS 27.0、Apple 芯片。两个内核都用 Go 1.27.3 从本地源码编译（mihomo v1.19.32，sing-box testing
`dfb80349`），本机回环、单连接，客户端与服务端各一个进程，每项 5 次取中位数：

| 链路 | mihomo | sing-box |
| --- | --- | --- |
| 直连转发 | 3.6 GB/s，每 GiB 0.41 s CPU | 6.9 GB/s，每 GiB 0.17 s CPU |
| AnyTLS | 1.53 GB/s，每 GiB 1.88 s | 1.48 GB/s，每 GiB 2.05 s |
| SS2022（aes-128-gcm） | 2.2 GB/s，每 GiB 1.08 s | 2.6 GB/s，每 GiB 0.89 s |
| 空闲常驻内存（每个进程） | 29 MB | 32 MB |

两项都远高于真实网络带宽，实际使用差别不大。TUN 性能需要 root，没有测；两者在 2026 年 9 月都换了新的协议栈。

近 12 个月（截至 2026-10-20）：mihomo 有 17 个正式版、787 次提交、89 位作者，最多的一位占约 78%；
sing-box 有 40 个正式版、848 次提交，约 96% 来自同一位维护者。

### 2026-10-22 P1

- `proxy-test` 198 项断言全部通过。完整 `run-tests.sh` 的 125 个 harness 里只有 `cleanup-walk-test` 失败
  （「discovery leaves every size pending」），干净的 HEAD `67bd55a5` 上同样失败，与本功能无关。
  lint 与 Model 纯度检查通过，Debug 构建没有新增警告。
- 官方发布包 `mihomo-darwin-arm64-v1.19.32.gz` 的 SHA-256 与锁定值一致；解压后 56.8 MB，go1.26.8 编译。
- `mihomo -t`：TUN 与仅端口两种配置都通过。组筛选里用占有量词 `a++` 时 ICU 接受、regexp2 拒绝，
  `-t` 直接 panic、退出码 2，报错带出错的正则，所以两段校验缺一不可。`-t` 会在 `-d` 目录写 `cache.db`。
- 本机回环端到端 37 项通过：订阅 HTTP 服务、mrs 规则集、由另一个 mihomo 提供的两个 ss 节点，全部在 127.0.0.1，
  端口独立，不碰系统网络和 Clash Verge Rev。
  - YAML 订阅、base64 分享链接订阅、分享链接本地文件都能解析；默认排除去掉了信息节点；订阅自带的组和规则被忽略。
  - 重命名、前缀、地区筛选、来源子集、成员策略、没有节点时的 `COMPATIBLE` 都与模型一致。
  - 每类流量命中预期的规则集和分流组；`PUT /proxies/route…` 后下一条连接即生效，不重载配置。
  - 国外 DNS 带 `#<百分号编码的策略名>` 时确实经该策略查询。
  - `subscription-userinfo` 解析为 `subscriptionInfo`；分组测速覆盖组内全部节点。
  - `PUT /configs?force=true` 后控制接口仍在；内核会从缓存恢复旧的选择，所以加载后必须再设置一次。
  - 内核没有访问外网，也没有下载 GeoIP 数据库。
- 据此修正的设计（已写入 Spec）：
  - 多个 provider 且有多条筛选时，mihomo 会把成员策略挪到节点之后；`exclude-filter` 也会删掉名字匹配的成员策略。
    所以地区与正则合成一条筛选，排除写成否定前瞻，`use` 按来源顺序列出。
  - 地区代码只按大写匹配，避免把「Contact us」当成美国。
  - `hosts` 会让内核提前得到目标 IP，`no-resolve` 的 IP 规则随之命中。做「配置覆写」（P5）时要在界面上说明。
  - 订阅和规则集下载失败后，内核按 10 秒起、翻倍、最长一个更新间隔退避重试，Tinycast 不用另做重试。

### 2026-10-22 P2

- harness：`proxy-test` 198 项、`proxy-api-test` 92 项、`proxy-service-test` 46 项断言全部通过。
- `Scripts/proxy-smoke.sh` 44 项通过，约 15 秒，全部在本机回环，不碰系统网络和 Clash Verge Rev：
  - 没有内核的包连接时报告缺少内核；从本地发布源（真实压缩包与 SHA-256）完成一次应用内安装后连接。
  - P1 的分流、改选、重载、正则拒绝、内核被杀后重启等检查都由 `ProxyManager` 驱动通过；TUN 模式的配置也过了 `-t`。
  - 一个能通过 `-v`、`-t` 但启动即退出的假内核被装上后自动删除，之前的内核重新运行且选择恢复；digest 不符的下载被拒绝，
    运行中的内核不受影响；恢复内置版本后在打包内核上重启，下载的版本全部删除。
- `Scripts/upgrade-mihomo.sh` 一条命令把打包内核从 v1.19.32 升到 v1.19.33，用时 26 秒：两个架构的压缩包都与 GitHub
  公布的 SHA-256 一致，`-v` 报告 `v1.19.33 darwin arm64`，LICENSE 未变，smoke 44 项通过。占用 47001 端口让 smoke
  失败时，`core.env`、`NOTICE.md` 和本地内核都还原到原来的版本。两个版本之间配置与控制接口只多了 tun 的 `dns-mode`。
  v1.19.33 修复了 crypto/tls 的 CVE-2026-97031、重载时 fake-ip 分配状态丢失和 DoH 拨号堆积，都与本功能有关。
- Debug 构建没有新增警告；`Contents/Helpers/mihomo` 是签过名的 v1.19.33（解压 56.8 MB），`codesign --verify --deep
  --strict` 通过。harness 与 smoke 结束后没有残留进程和钥匙串条目。
- 据此修正的设计（已写入 Spec）：
  - 不写 `proxy` 的 provider 下载会按分流规则走，可能经代理：订阅默认写 `proxy: DIRECT`，勾选「经代理更新」时才用默认策略。
  - mihomo 用 `COMPATIBLE`（实际是直连）顶替筛不出节点的组：策略组都写 `empty-fallback: REJECT`，什么都没有的组只放 `REJECT`。
  - URLSession 会因 HSTS 预加载把 `http://openai.com` 换成 HTTPS，绕过混合端口的 HTTP 代理，所以 smoke 用 `ai.test`。
  - 控制接口在 provider 加载完之前就会应答，选择可能暂时失败：失败的选择在下次刷新时重试。
  - 用户态内核的 socket 放在 `$TMPDIR/<bundle id>.proxy/`：Application Support 下的路径会超过 `sockaddr_un` 的 104 字节。
  - smoke 发现：选择内核时立刻删除被取代的下载版本，新内核起不来就无处回退。改为选中的内核启动成功后才删除。

### 2026-10-22 P4、P5

- harness：`proxy-test` 236 项、`proxy-api-test` 94 项、`proxy-service-test` 46 项断言全部通过；新增的是
  规则候选（站点后缀、二级后缀、IP 段、应用）、启动器的查询与剪贴板判断（脱敏）、策略节点池的匹配预览、
  经成员策略找到实际节点（含成环）。完整 `run-tests.sh` 127 个 harness 只有既有的 `cleanup-walk-test` 失败。
- `Scripts/proxy-smoke.sh` 54 项通过，新增 10 项都用真实内核：
  - 临时全局代理：`PATCH /configs` 后模式是 global、`GLOBAL` 选在默认策略、国内域名的连接日志是「using GLOBAL」；
    关闭后回到 rule，两次都不重载配置。
  - 本地节点文件改写后 `PUT /providers/proxies` 让内核立即读到新节点，不重载、不重启；写坏的文件被拒，
    提示里是内核的原因（`yaml: unmarshal errors … convert v2ray subscribe error: format invalid`），原有节点保留。
  - 换订阅链接时删除的缓存文件路径正是 provider 的 `path`。
- lint 通过（只剩长文案字面量的行宽提示，与上游同样写法）；Model 纯度检查为空；Debug 构建没有新增警告；
  新增 400 余条简体中文，`localization-test` 通过；`Localizable.xcstrings` 相对 HEAD 只有新增。
- 据此修正的设计：
  - mihomo 的 file provider 更新失败会返回 503 和原因，`sourceUpdate` 因此带上原因，内核多行的报错压成一行。
  - 「Resolution」「Pattern」在目录里已有上游译文（分辨率、规则），代理改用「DNS Mode」「Name Pattern」，
    避免同一个键在两处意思不同。
- 界面没有目视验收：不在本机运行 Dev 构建（用户之前要求删除，它也会和已安装的 Tinycast 争全局热键）。
  与 P3 的 TUN 验收一起，在用户在场时完成。

### 2026-10-23 P3（不安装部分）

- 只编译和测试，没有安装助手、没有以 root 运行任何东西、没有改动系统 DNS 或网络，Clash Verge Rev 照常运行。
- `proxy-helper-test` 151 项断言，进程内完成，不碰系统状态：
  - 模型：label 与路径（Dev、正式版互不干扰，控制 socket 路径不超过 `sockaddr_un`）、非法 identifier、签名要求原文、
    provider 文件名白名单、配置白名单（生成器的两种配置都通过；`external-controller` 等键、越界的 provider 与规则集路径被拒）、
    `record.json` 的开机判断、DNS 备份的还原条件、XPC 上的失败与状态编码。
  - 脚本：AppleScript 自己求值字面量，得到的 shell 用 `sh -n` 解析；含单双引号、反斜杠、`$(…)` 和反引号的路径原样到达；
    先校验签名、再移入、再运行；卸载先 bootout、再还原 DNS、最后删除。
  - 助手：匿名 XPC 监听，harness 二进制自己充当假内核。按哈希交付内核（哈希不符、要求签名而没有签名、不是内核都被拒），
    节点文件、启动与原地重载（相同配置不重载、内核拒绝时保留上一份）、socket fd 交给客户端后能访问控制接口、
    杀掉内核后按退避重启并推送、Tinycast 断开后停内核并还原 DNS、开启「退出后保持连接」时不停、
    别人改过的 DNS 不还原、主服务切换、同一次开机内恢复与新开机只还原 DNS、停止上个助手进程遗留的内核、
    签名不符、uid 不符和不是自己的助手都被拒且立即返回。
- `proxy-service-test` 50 项（内核安装器返回内存中算出的哈希）；完整 `run-tests.sh` 128 个 harness 只有既有的
  `cleanup-walk-test` 失败。
- Debug 构建没有新增警告；以 Tinycast Self-Signed 签名的 Release 构建通过 `verify-signature.sh`：助手与内核都有硬化运行时，
  identifier 分别是 `com.tinycast.app.proxy-helper`、`com.tinycast.app.mihomo`；把助手改签成别的 identifier 的副本被拒。
  `CODE_SIGNING_ALLOWED=NO` 的 Debug、Release 构建通过。
- lint 只剩长文案字面量的行宽提示；Model 纯度检查为空；`xcodegen generate` 结果不变；新增 35 条简体中文，
  `localization-test` 通过。
- 实现中定下的做法：
  - `grant.json` 由校验过的 root 副本用自己的签名身份写入，Tinycast 只传 uid，root 不信任调用方给的文本。
  - plist 用 `KeepAlive: {SuccessfulExit: false}`：加载（含开机）时运行一次，还原崩溃留下的 DNS 占位；
    只在同一次开机内恢复内核；空闲 10 秒正常退出，下次消息再由 launchd 启动。
  - 状态推送带 revision：推送经各自的 Task 回到主线程，迟到的旧状态不能覆盖新的。
  - 安装或更新助手前先停 TUN 内核，装完再连接；卸载同样先停，让助手自己还原 DNS。
  - 助手只在协议版本变化时提示更新，所以助手的任何改动都要提高 `ProxyHelperWire.version`。
  - `verify-signature.sh` 在 `set -o pipefail` 下不能把 `codesign` 直接管道给 `grep -q`：grep 先退出，
    codesign 收到 SIGPIPE，整条管道判为失败。先取输出再 grep。
- 待用户在场：安装助手（会请求管理员密码）、退出 Clash Verge Rev 后做 AC-1、AC-6、AC-7，以及 P4、P5 和 TUN 一组的界面目视验收。

### 2026-10-23 原生验收与界面复查

- 用户退出 Clash Verge Rev 并在设置里安装了助手（一次管理员授权），之后由 TUN 内核承载本机网络。
- AC-1：不设代理访问 Google 返回 204；系统解析和发往 `8.8.8.8` 的 UDP 查询都得到 198.18 段的 Fake-IP；
  国内网站直连 200；国内、国外两个出口地址不同（只比较，不打印）。
- AC-6：安装只弹一次授权；助手副本满足签名要求；非 Tinycast 签名的探针被拒；普通用户进不去 root 目录、连不上控制 socket。
- AC-7（本机实测）：
  - 开启「退出 Tinycast 后保持连接」后退出 Tinycast：root 内核、TUN、DNS 占位都在，Google 照常 204；换装新构建再打开，
    接回同一个内核进程，不重启，「已连接」显示原来的启动时间。
  - 关闭该开关后退出：5 秒宽限后内核停止、TUN 拆除、Wi-Fi 的 DNS 还原为空（原本就没设）；
    开启「Tinycast 启动时连接」后重新打开即自动连上。
  - 设置里「断开」还原 DNS、拆除 TUN，「连接」恢复；「重新启动」换新内核进程后立即恢复。
  - root 内核崩溃后的退避重启只在 `proxy-helper-test` 里验证（本机杀 root 进程需要管理员权限）。
- 界面复查：按上面「界面复查」逐项截图核对，导入了一份带代理组和规则的测试文件（HUD「已添加「tc-import-test」：
  只使用其中的 2 个节点」，「文件内容」列出 1 个代理组、2 条规则和设置项），核对后删除；「立即更新」后 17 个规则集
  均已下载、更新时间刷新；在 TUN 日志里看到了两条拨号失败的警告。
- 测试：`proxy-test` 新增节点文件计数与台湾旗帜，`proxy-service-test` 新增规则集更新与日志流，
  `Scripts/proxy-smoke.sh` 新增规则集下载与「立即更新」两项，共 56 项通过（它的编译清单补上 P3 起用到的 `ToolRunner`）；
  完整 `run-tests.sh` 128 个 harness 只有既有的 `cleanup-walk-test` 失败。Debug 与签名的 Release 构建没有新增警告，
  `verify-signature.sh` 通过；lint、纯度检查、`xcodegen` 稳定性通过；新增约 50 条简体中文，`localization-test` 通过。
- 未做：助手卸载后无残留（需要管理员密码）；未装助手时 TUN 开关置灰的样子只能在卸载助手后目视。

### 2026-10-24 规则来源调研与 rebase

- meta-rules-dat 的 `meta` 分支（GitHub API 读目录树）：`geo/geosite` 有 5770 个文件，即 1923 个分类各有 mrs、yaml、list
  三份（另有一个 classical 目录）；`geo/geoip` 有 781 个文件，即 260 个分类。规则库要用的七十多个名称逐一核对过
  （openai、anthropic、google-gemini、github-copilot、netflix、hbo、primevideo、epicgames、paypal、
  category-cryptocurrency、category-scholar-!cn 等都在）；`gemini`、`copilot` 不存在。不是国家的 geoip 有 cloudflare、
  cloudfront、facebook、fastly、google、netflix、private、telegram、tor、twitter。
- 仓库活跃度（GitHub API）：meta-rules-dat 5.4k 星，10-23 推送；Loyalsoldier/clash-rules 28.9k，10-22；
  blackmatrix7/ios_rule_script 28.4k，10-19；SukkaW/Surge 4.6k，10-23；ACL4SSR 6.8k，10-17；
  DustinWin/ruleset_geodata 1.4k，10-22。
- 格式：mrs 是 zstd 压缩，解压后开头是 `MRS\x01` 和类型字节（mihomo `rules/provider/mrs_reader.go`）。Foundation 解不了
  zstd，所以 mrs 只认 zstd 魔数，类型按路径判断。SukkaW 的 Clash 文本是 `#` 注释加 `DOMAIN-SUFFIX,…` 行（实取）；
  Loyalsoldier 的 `.txt` 实为 YAML `payload:`，blackmatrix7 的 Clash 版是 YAML 混合规则（按两仓库公开的格式在 harness
  里构造样本：当时用户已断开代理，直连访问 raw.githubusercontent.com 与 jsDelivr 被重置）。
- 结论（D13）：规则内容本来就是订阅，内核每天经默认策略更新；写死的只是分类表。做规则库和任意链接，
  不订阅整套分流方案。
- rebase：见 v3 一节第一项。rebase 后 Debug 构建无警告通过；`proxy-test`、`proxy-api-test`、`proxy-service-test`、
  `proxy-helper-test` 通过。

### 2026-10-24 v3 原生验收与整体界面复查

用户的代理此前已断开（`connected=false`、功能关闭），开发期间不重连。验收用隔离的测试档案：备份
`Proxy/` 目录后，来源换成指向回环 ss 节点（另起一个 mihomo 监听 47001、47002，并有一个不存在的 47009）的本地文件，
关闭 TUN，混合端口改为 47790。系统代理与 DNS 全程未变，没有新建 utun。验收结束后还原备份并恢复功能关闭。

- 窗口五页、菜单栏（含网速）、启动器状态卡与 ⌘K 菜单、设置 › 代理，在未连接与已连接、深色与浅色下逐页截图核对。
  网址测试（`chat.openai.com` 命中 AI 服务到具体节点，`www.example.org` 命中我的规则）、点选节点、改分流目标、
  恢复推荐分流（确认对话框）、规则库搜索与添加、从链接添加（读取失败时按扩展名猜测）、我的规则编辑、
  活动页右键为连接加规则、三种模式切换与流向图汇聚都实际操作过。
- 发现并修复：
  - 点选节点或改分流目标后，下一次刷新把内核里的选择改回旧值：只改选择时配置的 `reloadKey` 不变，
    `applied` 没有更新，`refresh` 按旧配置重放。现在每次 reconcile 都更新 `applied`；冒烟测试加了两项回归检查。
  - 直连分流里国外域名（如 `www.apple.com`）按 `nameserver-policy` 走境外 DNS 后拨号超时：加
    `direct-nameserver`（国内 DNS）与 `direct-nameserver-follow-policy: false`，隔离实例上复现并验证后改进生成器。
  - 节点名自带国旗时界面又加一面（节点卡、菜单、启动器、活动、网址测试统一用 `Node.label`，台湾不显示旗帜）；
    端口显示成「47,790」；卡片网格行内居中导致顶边错位；不可用的链接按钮仍是蓝色（改为隐藏）；
    启动器 ⌘K 菜单里模式行与上方图标不对齐；未连接时的时长文字（「0 秒钟后」）改为实时的已连接时长；
    添加的分流排在已包含同一规则集的分流之后而永远不命中（改为插到它前面）；为已走代理的连接加规则时默认目标
    改为直连；策略编辑只列出节点池里出现的地区；没有订阅时不显示「更新订阅」；重新打开应用时聚焦代理窗口；
    节点卡片补上无障碍名称；已关闭的行与卡片统一淡化程度；「核心」状态卡直接打开设置的内核一节。
  - 上次退出时已连接、但「Tinycast 启动时连接」关闭时，启动后未连接却仍显示「断开」：启动不连接时清除旧的连接意图
    （冒烟测试新增一项）。规则值无效时的提示改为每种类型一句完整的话，不再把译名强制小写拼进句子。
  - 活动页里内核自己的连接（规则集下载、测速，`metadata.type` 为 `Inner`）在「分流」列显示成模式名「规则」，
    像是命中了规则：现在显示为「内核」（`proxy-test` 新增一项）。
- 本地化：`sync-strings.sh` 后删除 92 个代理旧版的陈旧键，539 个键补齐 7 至 8 种语言；计数改为复数变体
  （两个计数的用 substitutions），去掉「1 个 / N 个」分支。目录按 Xcode 原格式与原有键序写回，diff 只有新增。

### 2026-10-24 交互、视觉与易用性复查（第二轮）

按用户的六点反馈与整体复查修改，用户本人的订阅（103 个节点）连接在混合端口上做原生验收（未开 TUN，系统代理与
DNS 未动）。

- 全屏：从全屏应用里打开或唤起窗口时看不到。根因是打开窗口时激活策略从附件切成常规（为了 Dock 图标），
  常规应用在已激活状态下新建的窗口落到普通桌面，且不切换过去。用一个常驻的附件测试程序（由不激活的全空间面板上
  的按钮触发）复现了全部路径，比较了 `moveToActiveSpace`、`fullScreenAuxiliary`、临时 `canJoinAllSpaces` 与相对
  排序：只有 `.moveToActiveSpace` 让新开、激活后新开、子面板和再次唤起都一致可见（切到窗口所在桌面）；
  `fullScreenAuxiliary` 反而让激活后新开的窗口落到别处。上游 `AppWindowController` 只加这一项。原生验收覆盖：
  启动器打开、代理窗口打开编辑面板、代理窗口打开设置、设置打开代理窗口、回到全屏终端后再唤起、设置窗口全屏时
  打开代理窗口及其编辑面板。
- 工具栏：连接开关改为按钮样式的电源开关，与模式分段控件同为玻璃控件。
- 流向图：策略改为不透明的块，线条在块的两侧接入接出，出口也成了不透明的胶囊；「via」移到悬停提示。
  网址测试从分流页移到概览的流向卡片里，输入网站或 IP 后点亮命中的那一行到策略再到出口的整条路径（拒绝为红色，
  连接失败标红），并在上方给出文字路径；结果到行的映射 `ProxyProbe.highlight` 放在 Model 里并有测试。
- 节点页：策略标签改为原生分段控件（放不下时为弹出菜单），「全部节点」改为打开节点池面板；策略摘要卡去掉徽章；
  可选策略为一行芯片；节点为单行芯片，按地区折叠（节点多时只展开在用节点所在的地区，节点少时全部展开，可全部
  展开或收起），地区行显示数量和最快延迟。节点名拆成短名与灰色的供应商备注（`ProxyNodeName`，只在冒号、竖线或
  破折号前是含数字的短名时拆），截断在尾部。经由其他策略实际在用的节点带描边。
- 台湾旗帜：系统字形本身被替换（按字形名直接绘制也是方框），`ProxyFlagArtwork` 按测得的系统旗帜造型（字宽、
  单个波浪、迎光面提亮、圆角）自绘，窗口、启动器和菜单栏里都用它；纯文本仍不带。
- 策略编辑器：节点范围为「全部节点 / 按地区或名称 / 不含节点」；地区只列节点所在的地区，带旗帜和数量，
  未连接时从菜单添加；其他选项为可删除的标签；字段统一为编辑器的行样式，并实时预览匹配的节点。
- 其他：macOS 27 默认隐藏菜单项图片，菜单栏的策略色点和地区旗帜改为显式可见；菜单副标题、提示和启动器卡片用
  短节点名；来源卡片「编辑…」改为「设置…」以免与「编辑文件…」混淆；我的规则为空时不再重复显示「编辑…」；
  活动页在未开 TUN 时说明只有设置了代理端口的应用会出现。
- 本地化：新增 20 个键补齐 8 种语言，删除 12 个陈旧键，上游条目逐字节未变。
- 另见：重新启动后第一次按 ⌘空格 未打开启动器（合成按键下可复现，第二次正常），属于上游启动器，未在此改动。

### 2026-10-24 测速、节点来源与粘贴

用户反馈：自动最快选了美国节点、节点没有延迟、看不到节点来自哪个来源、规则编辑器里从剪贴板历史回车粘贴和
⌘V 都没进输入框。用用户本人的订阅（103 个节点，一个本地文件来源）原生验收。

- 测速：同一来源上的几个自动策略各自把测速任务注册到来源上，mihomo 按测速地址合并它们的节点过滤条件，
  「全部节点」的空过滤被「美国」「韩国」两个过滤取代，启动时只测了这 12 个节点，自动最快只能在其中选；
  手动「测速全部节点」走的来源测速也只测这 12 个。现在每个来源自带 `health-check`（默认测速地址，间隔取来源上
  最勤的自动策略，lazy），取全部节点的池也显式写 `.*`。连接或重载后 `ProxyManager` 等内核的首轮测速结束，再让
  最快节点策略丢掉缓存的选择（`DELETE /proxies/{name}`，否则内核十秒内沿用测速前的选择），然后刷新。
- 节点芯片：未测速的显示「—」；首轮测速期间策略摘要卡显示进度。启动器的节点列表打开时刷新一次。
- 来源：节点悬停提示总写来源和类型；策略摘要卡列出节点来自哪些来源，点按跳到订阅页；节点来自多个来源时，
  节点区可以只看其中一个。节点池只有一个来源时在搜索框旁标出它，行的悬停提示也写来源。
- 粘贴：启动器从 Tinycast 自己的窗口唤出后执行粘贴，会不恢复焦点地收起，AppKit 把键盘焦点交给主窗口，跳过
  上面的编辑面板；而且启动器持有焦点期间，代理窗口和编辑面板里的 SwiftUI 输入框会丢掉编辑状态（设置窗口工具栏
  的搜索框不会），合成的 ⌘V 和之后手动按的 ⌘V 都无处可落。面板保持焦点时 ⌘V 本来就正常。现在启动器唤出时记下
  原窗口正在编辑的输入框和光标，收起时若它持有焦点、又是从自己的窗口唤出的，就把焦点和输入框一起还回去（按 Esc
  收起也一样），只要这期间那个窗口里没有别的控件拿到焦点。另一个原因由诊断日志确认：恢复成功后约 0.1 秒焦点
  又被抢走，是收起后立即「返回主搜索」时模式切换给已隐藏的启动器搜索框设了焦点（SwiftUI 会因此让其他窗口的输入框
  失去焦点；返回主搜索设了延迟的用户，会在延迟到点时于别的窗口里突然丢焦点）。现在启动器不可见时不设焦点。
  原生验收：规则编辑器里先输入 ab，唤出启动器 → 剪贴板历史 → 回车，得到 aburtoken.ai 且焦点留在输入框；随后
  ⌘V 继续粘贴；Esc 收起启动器后输入框仍在编辑。另见：其他应用在前台时，合成按键进不了启动器，改动前的版本
  同样如此（用同一提交单独构建对照），属于测试环境，真实键盘不受影响。
