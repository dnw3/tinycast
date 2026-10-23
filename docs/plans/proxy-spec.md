# 代理（TUN）Spec

状态：2026-10-21 设计已确认；2026-10-22 P1（纯模型与配置生成）、P2（用户态内核、控制接口、内核更新）、P4（启动器）与 P5（设置）完成；2026-10-23 P3 的 TUN 助手代码与测试完成并通过原生验收。2026-10-24 用户认为界面不直观、不美观，
确认 v3 重新设计（D9–D14）：交互以[设计稿 v3](proxy-redesign/index.html)为准，[v2 原型](proxy-prototype/index.html)只作历史参考。
实施顺序与验证记录见 [Plan](proxy-plan.md)。功能文档 [proxy.md](../features/proxy.md) 已建立，描述已实现的部分并以它为准。

## 目标与范围

Tinycast 内置一个代理客户端：自己托管 mihomo 内核，用 TUN 接管整机流量；节点、策略、分流三层分开配置，
在代理窗口里管理，在菜单栏、启动器和窗口里即时切换。

- **一键可用。** 添加订阅后套用默认方案即可连接；浏览器、终端、UDP 都经过 TUN。
- **灵活。** 订阅只提供节点。策略和分流独立于订阅，可以任意搭配；多个订阅和本地文件合并成一个节点池。
- **状态优先、随手可换。** 菜单栏、代理窗口、启动器都先给状态：连接与否、模式、出口节点与延迟。换节点、换模式、
  给某类流量换策略、加规则都能两步完成；启动器里都是命令，都能绑热键。
- **独立。** 不需要 Clash Verge Rev 或任何其他客户端。

不做，或留给以后再定：

- NetworkExtension、System Extension（见 D3）。
- 系统代理：未安装 TUN 助手时只开混合端口供手动使用，不修改系统代理设置（D4）。
- 订阅自带的策略组和规则（D5）；订阅整套分流方案（D13）。
- 从 Clash Verge Rev 迁移（用户要求）。
- 覆写脚本、远程控制、多设备同步。

## 已确认的决定

| 编号 | 决定 | 依据 |
| --- | --- | --- |
| D1 | 内核用 mihomo（MetaCubeX，GPL-3.0），作为独立进程运行，不链接进 Tinycast | 2026-10-21 用户确认选型。内核原生解析 Clash 订阅与分享链接，provider 可合并、筛选，有 5 类策略组和 REST 控制接口。sing-box 没有内核级订阅，配置几乎每个小版本都有破坏性迁移。对比数据见 Plan |
| D2 | 不依赖、也不迁移 Clash Verge Rev | 用户要求 |
| D3 | root 组件用传统 LaunchDaemon，经一次管理员授权安装 | 没有 Apple 开发者账号。NetworkExtension 需要受限 entitlement；SDK 的 `SMAppService.h` 写明 "Apps that contain LaunchDaemons must be notarized" |
| D4 | TUN 是唯一的接管方式；未安装 TUN 助手时只提供混合端口 | 用户要求：只有系统代理作用不大 |
| D5 | 三层模型：节点 → 策略 → 分流，订阅只提供节点 | 用户提出，2026-10-21 确认原型 |
| D6 | 内核随 Tinycast 打包，版本与 SHA-256 锁定在 `Vendor/mihomo/core.env` | 首次使用时还没有代理，境内直连 GitHub 下载内核不可靠。arm64 安装包压缩后约增加 21 MB，解压 56.8 MB |
| D7 | 分流规则来自 MetaCubeX/meta-rules-dat 的 mrs 规则集，由内核每天经默认策略更新 | 仓库持续维护（2026-10-23 仍有提交）。2026-10-24 复核：geosite 有 1923 个分类、geoip 260 个，每个分类各有 mrs、yaml、list 三种文件 |
| D8 | 内核升级要省事：维护者一条命令升级打包内核；用户在设置里检查更新、下载官方发布包，起不来自动回退，内置内核始终保留 | 2026-10-22 用户要求考虑内核升级的便捷性。mihomo 一年约 17 个正式版，协议支持和修复都随版本发布 |
| D9 | 管理界面放进独立的代理窗口（概览、节点、分流、订阅、活动），设置 › 代理只留偏好 | 2026-10-24 用户确认 v3 设计稿：原界面几乎全是设置表单，状态要拼着看，三层关系看不出来 |
| D10 | 模式为规则、全局、直连三选一并持久保存；去掉「方案」和「临时全局代理」，保留「恢复推荐分流」 | 2026-10-24 用户确认。原来「方案：全局代理」和「临时全局代理」重名，又没有直连模式 |
| D11 | 活动页（连接列表，可为连接加规则）首批实现 | 2026-10-24 用户确认 |
| D12 | 代理有独立的菜单栏图标，默认关闭 | 2026-10-24 用户确认（默认关闭是用户的选择） |
| D13 | 分流规则来源：内置规则库、任意 geosite 或 geoip 名称、任意规则集链接（自动识别格式与类型）；不订阅整套分流方案 | 2026-10-24 用户问内置分流能否改成订阅。规则内容本来就是订阅的；整套方案会带入别人的策略组与顺序，与 D5 冲突。分析见 Plan 验证记录 |
| D14 | 地区表扩充到 79 个，识别简繁中文、英文、城市与常见代码；策略编辑只列出节点池里出现的地区（及已选的） | 2026-10-24 用户要求多补地区 |

## 三层模型

### 节点来源

- 两种来源：订阅（URL）和本地文件。本地文件可以是 YAML 的 `proxies:` 列表，也可以每行一个分享链接。
  下载、解析和格式转换都由内核完成：mihomo 先按 YAML 解析，失败后按分享链接或 base64 解析。
- 每个来源可以勾选。勾选的来源合并成节点池。
- 每个来源可以设置包含、排除、重命名和名称前缀，在节点进池之前生效，分别对应 provider 的 `filter`、
  `exclude-filter`、`override.proxy-name` 和 `override.additional-prefix`。包含和排除匹配来源原本的节点名，
  内核先筛选、再重命名、最后加前缀。订阅默认排除名称里带
  「剩余、到期、过期、官网、流量、重置」的信息节点。
- 同名节点：mihomo 按名称选择节点，跨来源同名时后一个无法被选中。Tinycast 读取节点后检测重名，
  提示并一键给后加入的来源填上前缀（P5）。
- 更新：每个订阅有自己的间隔（默认 12 小时），可选「经代理更新」。不勾选时 provider 写明 `proxy: DIRECT`：
  不写的话内核按分流规则发出下载请求，订阅可能经代理下载。更新失败时内核继续使用上次的缓存。
- 流量和到期时间来自内核从 `subscription-userinfo` 响应头解析出的字段。
- 订阅链接只存钥匙串（`KeychainSecretStore` 新增 scope `proxy-subscriptions`，按来源 id）。
- 来源只贡献节点：文件或订阅自带的端口、DNS、代理组（`proxy-groups`）、规则（`rules`、`rule-providers`）和代理集
  （`proxy-providers`）都不读取（2026-10-23 用户确认「只用节点，讲清楚」）。界面要说清楚：导入后的 HUD 写明只用了其中的
  节点；来源编辑器的「文件内容」和节点文件编辑器的底部按顶层键逐行计数（`ProxyNodeFileOutline`，不解析 YAML），
  列出文件里不会使用的代理组、规则、规则集、代理集和其他设置；来源一节的说明也写明这一点。
- 节点页的「查看节点…」列出内核当前持有的节点池：按地区分组，可搜索名称、地区或协议，有多个来源时可按来源筛选，
  显示协议、UDP 与最近一次测速；来源的右键菜单可直接看该来源的节点。

### 策略

- 类型：手动选择（select）、自动选择（url-test，带容差）、故障转移（fallback）、负载均衡
  （load-balance，consistent-hashing）。
- 节点范围：全部来源或指定来源；按地区（内置地区表，可多选）或自定义正则筛选，两者取并集；可排除。
  映射为按来源顺序列出的 `use` 和一条 `filter`：地区与正则合成一条，排除写成开头的否定前瞻。不用多条筛选，
  也不用 `exclude-filter`：前者会把成员策略挪到节点之后，后者会删掉名字匹配的成员策略。地区代码（HK、JP…）
  只按大写匹配。
- 成员策略：一个策略可以把其他策略排在节点之前。默认的「默认代理」第一项是「自动最快」；
  「稳定优先」可以是「香港优选 › 日本优选 › 新加坡优选」，不含池里的节点。成员关系不能成环。
- 测速：URL 默认 `https://www.gstatic.com/generate_204`，间隔 300 秒，容差 50 ms；`lazy: true`，
  没有被任何分流或规则使用的策略不测速。
- 内置目标：直连、拒绝。
- 每个策略有一种颜色（6 色），出现在启动器、下拉框和设置里，方便对应。

### 分流

- 一个分流 = 一个分类（一组规则集）→ 一个目标（策略、直连或拒绝）。从上到下匹配，「其他流量」固定在最后兜底。
- 内置分类与推荐分流的默认目标：

| 分类 | 规则集（meta-rules-dat） | 默认目标 |
| --- | --- | --- |
| 广告拦截 | geosite `category-ads-all` | 拒绝 |
| 局域网 | geosite `private`、geoip `private` | 直连 |
| AI 服务 | geosite `category-ai-!cn` | 默认代理 |
| 流媒体 | geosite `netflix` `youtube` `disney` `spotify` `tiktok`、geoip `netflix` | 默认代理 |
| Telegram | geosite `telegram`、geoip `telegram` | 默认代理 |
| GitHub | geosite `github` | 默认代理 |
| 苹果服务 | geosite `apple` | 直连 |
| 国外网站 | geosite `geolocation-!cn` | 默认代理 |
| 国内网站 | geosite `cn`、geoip `cn` | 直连 |
| 其他流量 | `MATCH` | 默认代理 |

- **规则库**（`ProxyRuleCatalog`，D13）：常用服务与类别四十多项（AI、流媒体、社交、开发、平台、游戏、国内服务、金融等），
  各有中文名、图标和中英文检索词，选中即生成一个分流；还可以直接输入任意 geosite 或 geoip 名称（先确认 meta-rules-dat
  里有这个文件再添加）。都用 meta-rules-dat 的 mrs，内核每天更新。
- **从链接添加**：任何仓库的规则集链接（Loyalsoldier/clash-rules、blackmatrix7/ios_rule_script、SukkaW 的
  ruleset.skk.moe 等）。添加时下载开头一段识别：zstd 开头的是 mrs，类型按路径判断（geoip 为地址段，其余为域名，可以改）；
  `payload:` 开头的是 YAML，不论扩展名（Loyalsoldier 的 `.txt` 就是这样）；其余按每行一条的文本。条目带 `DOMAIN-SUFFIX,`
  这类前缀的是混合规则，全是地址段的是 ipcidr，否则是域名。名称默认取文件名。
- **不订阅整套分流方案**（ACL4SSR 那种模板）：它会带入别人的策略组和顺序，与三层模型冲突，更新时还会打乱用户调好的顺序。
  以后需要时做一次性导入。
- IP 类规则集带 `no-resolve`，只有「国内网站」的 geoip `cn` 会为未命中的域名做一次解析，把境内 IP 交给直连。
- 运行时切换：每个分流生成一个隐藏的 select 组（`route/<分流 id>`），选项是全部策略、直连和拒绝，规则指向这个组。
  在启动器里换策略只调用一次 `PUT /proxies/{组名}`，不重载配置。Tinycast 同时保存选择；下次生成配置时把它排在首位，
  加载后再设置一次。
- **恢复推荐分流**：内置分类回到上表的顺序与去向，自定义分流保留在前面。原来的「方案」选择器去掉（D10）：
  「全局代理」与全局模式重复，「国内直连」与推荐分流只差广告拦截和苹果服务直连。

### 我的规则

- 每条规则：类型（域名、域名后缀、域名关键词、IP 段、进程名）、内容、目标。全部排在分流之前。
- 规则内容和策略名称都不能包含逗号、换行、`#`、`&`、`=`，以免改写规则或 DNS 语法。
- 测试：输入域名或 IP，按 Tinycast 的模型给出第一条命中的规则（纯函数）。规则集由内核匹配，这里不判断；
  用内核的 `/connections` 做运行时核对留待以后。
- 快速添加：启动器命令「添加分流规则」，默认取 Safari 或 Chromium 系浏览器前台标签页的域名；读不到时留空。
  列出可选的匹配方式（站点及子域名、该主机及子域名、仅该域名、关键词；地址为 IP 段，单个词为应用），回车进入策略列表，
  回车保存。新规则排在最前；同类型同内容的规则只保留一条，改到最前。

### 模式

- 规则（默认）、全局、直连三选一（D10），持久保存在 `profile.json`，重新打开和重新连接后保持。
- 全局：`GLOBAL` 组选默认策略，所有流量走它。直连：所有流量直连，TUN 与 DNS 接管不变，比断开更适合临时不走代理。
- 配置写入当前模式；切换只发 `PATCH /configs`，不重载配置，加载后再设一次。
- 菜单栏、窗口工具栏、启动器命令三处都能切换。不在规则模式时，分流页顶部说明分流暂不生效，流向图的线汇到同一个出口。

## 运行架构

### 进程与权限

```text
Tinycast（当前用户）                        TUN 助手（root，LaunchDaemon）
 ├ ProxyManager 等可观察状态                 ├ XPC：校验客户端签名与 uid
 ├ 生成配置（纯函数） ── 配置字节 ──────▶     ├ 写入自己的 root 目录（0700）
 ├ 控制接口客户端 ◀── 已连接的 socket fd ──   ├ 以 root 运行 mihomo（TUN），崩溃后重启
 └ 未安装助手：直接运行 mihomo（仅混合端口）  └ DNS 占位与还原
```

- **用户态内核**：未安装助手，或关闭了 TUN。Tinycast 以子进程运行内核（打包的 `Contents/Helpers/mihomo`，
  或「内核更新」下载的更新版本），工作目录 `~/Library/Application Support/<bundle id>/Proxy/Core/`（0700），
  只开混合端口，不启用 TUN。
- **助手内核**：TUN 开启。助手以 root 运行自己目录里的内核副本。
- Tinycast 的设置是唯一的期望状态。助手只负责执行，并保存最近一次配置，以便内核崩溃后不依赖 Tinycast 自行恢复。

### TUN 助手

- **形态**：命令行工具 `TinycastProxyHelper`，随 app 打包在 `Contents/Helpers/`，签名 identifier 为
  `<bundle id>.proxy-helper`（构建阶段「Embed TUN helper」签名）。安装时复制到
  `/Library/PrivilegedHelperTools/<label>`，plist 写入 `/Library/LaunchDaemons/<label>.plist`。
  label 为 `<bundle id>.proxy-helper`，Dev 与正式版互不干扰。
- **安装与卸载**：先用 `DialogController` 说明，再用 `osascript … with administrator privileges` 运行生成的脚本，
  路径与参数全部单引号转义（与 Cleanup 的系统更新残留同一写法）。只在首次安装和助手协议版本升级时请求授权。
  - 安装：把 app 包里的助手复制成同目录下的临时文件，改为 root:wheel 755，`codesign --verify --strict -R`
    核对它是这个 Tinycast 的签名者签的（identifier 与叶证书），通过后才原子移入；再以 root 运行这份副本的
    `--install <uid>`：它核对自己的签名，写入 `grant.json` 和 launchd plist；最后 `launchctl bootstrap`
    （刚 bootout 的 job 可能短暂拒绝，重试 5 次）。root 只运行校验过的副本，因为用户能替换 app 包里的文件。
  - 卸载：`launchctl bootout`（助手收到 SIGTERM 时停内核、还原 DNS），再运行 `--restore-dns` 兜底，
    最后删除 plist、二进制和 root 目录。
- **目录**：`/Library/Application Support/Tinycast/<label>/`，root:wheel 0700，已存在的路径必须是 root 自己的目录、
  不能是链接。其中：`core/mihomo` 是校验过的内核副本；`config.json` 权限 0600；`providers/`、`rules/` 是内核数据；
  `run/core.sock` 是控制接口；`record.json` 记录期望状态、DNS 备份和已校验内核的哈希与版本；`grant.json`
  是安装时写入的客户端身份（Tinycast 的 identifier、叶证书 SHA-1）与 uid；`core.log`、`core.pid`。
- **XPC**：`NSXPCListener(machServiceName: label)`。监听端 `setConnectionCodeSigningRequirement` 使用
  `grant.json` 记录的 Tinycast 身份，不符合的连接到不了代理对象；再校验 `effectiveUserIdentifier` 等于安装用户。
  Tinycast 一端用 `.privileged` 连接，并要求对方是同一签名者签的 `<bundle id>.proxy-helper`。
- **接口**（`ProxyHelperWire.version`，不一致即提示更新助手）：`handshake`；`status`（另有推送，带递增的
  revision，迟到的旧状态不会覆盖新的）；`installCore(fileHandle, sha256, signed)`；`writeFile(name, data)`、
  `removeFile(name)`，名称只允许 `src-<8 位小写十六进制>.yaml`；`start(config, placeholderDNS, outlivesClient)`、
  `stop`；`openController() → FileHandle`。卸载由外部脚本完成。
- **配置白名单**：`start` 只接受 `ProxyConfigBuilder` 会写的顶层键（因此没有 `external-controller`、
  `external-ui`、`secret`、`listeners` 等），proxy provider 的路径必须是 `providers/<名称>.yaml`，
  rule provider 的路径必须是 `rules/<名称>.<格式>`。运行中的内核收到不同的配置才重载，内核接受后才写回文件。
- **内核副本**：助手把 Tinycast 传来的 fd 内容复制到自己目录里的临时文件，校验它的 SHA-256 与 Tinycast
  随 fd 传来的哈希一致，`-v` 必须报告本机架构的 mihomo，通过后再原子替换。打包内核还要校验代码签名
  （`<bundle id>.mihomo`，叶证书与客户端一致）。下载的官方内核没有 Tinycast 的签名，只认这个哈希，
  所以 Tinycast 只在下载并校验发布包的同一次运行里、用内存中算出的哈希交出它，从不对磁盘上的副本重新计算；
  助手缺这个版本、本次运行又没有它的哈希时（例如之后才安装助手），改用打包内核，「检查更新」可以重新下载。
  助手从不执行 app 包或 Tinycast 目录里的文件，因为普通用户能替换它们。
- **监管**：内核异常退出后按 1、2、4…60 秒退避重启，使用最近一次配置；5 分钟内退出 5 次后停止并上报。
  每次启动都会累加 launch 计数，Tinycast 据此在内核重启后重新应用选择。
- **生命周期**：plist 写 `KeepAlive: {SuccessfulExit: false}`，因此 launchd 加载时（含开机）运行一次：
  上次崩溃留下的 DNS 占位在此还原；同一次开机（`kern.bootsessionuuid`）内助手崩溃重启时恢复内核，新的开机不恢复，
  等 Tinycast 来要。没有内核要跑、也没有客户端连着时，10 秒后正常退出，launchd 下一条消息再启动它。
  Tinycast 断开（退出或崩溃）5 秒后，没有开启「退出 Tinycast 后保持连接」就停止内核并还原 DNS。
  开启时内核继续运行，Tinycast 重新打开后接回它。
- **内核参数**：从不传 `-post-up`、`-post-down`；不设置 `SAFE_PATHS`；环境变量只有 `HOME`；`-d` 指向 root 目录，
  因此 provider、外部 UI 和证书路径都被限制在其中。
- **控制接口**：内核只开 Unix socket（`-ext-ctl-unix <root>/run/core.sock`），不开 TCP。socket 所在目录 0700，
  只有 root 能连接；助手连接后把 fd 经 XPC 交给 Tinycast，每个请求一个连接。本机其他进程，包括同一用户的进程，
  都无法控制 root 内核。
- **日志**：root 内核的日志在 root 目录里，普通用户读不到。TUN 内核运行时，Tinycast 经控制接口订阅
  `/logs?level=warning`（与配置的 `log-level` 一致，不记录每条连接），逐条加上本地时间追加到
  `Proxy/Core/tun-core.log`（0600，超过 8 MB 从头写），流断开（内核重启）后 2 秒重连。「显示日志…」打开最近写过的那份
  内核日志。订阅前产生的启动期警告记不到；规则集是否下载成功由分流页的规则集状态说明。
- **已知限制**：内核自带的 `/upgrade` 接口会就地替换正在运行的二进制：用户态内核在 app 包里，替换会破坏签名封装；
  root 内核的副本只该由助手校验后替换。只有持有 fd 的 Tinycast 能调用它，Tinycast 不调用，升级只走「内核更新」；
  助手每次启动内核前校验哈希，发现被替换就拒绝启动。

### DNS

- 默认 Fake-IP（`198.18.0.1/16`），`fake-ip-filter` 内置局域网、NTP、连通性检测等常见项。
- 国内 DNS（`nameserver`、`proxy-server-nameserver`）默认 `223.5.5.5`、`119.29.29.29`。`default-nameserver`
  取其中以地址给出的服务器（可带端口或 `udp://`、`tcp://`），一个都没有时用这两个默认地址。
  国外 DNS 默认 `https://1.1.1.1/dns-query`、`https://8.8.8.8/dns-query`，经默认策略解析：
  `nameserver-policy` 中国外网站规则集对应 `<地址>#<默认策略组>`。
- **DNS 占位**：macOS 上，主网络服务的 DNS 是局域网地址时，查询不经过 TUN，Fake-IP 就会失效。
  连接 TUN 时由助手把主服务（SystemConfiguration 的 `PrimaryService`）的 DNS 设为 `223.5.5.5`，这个地址进入 TUN
  后被劫持；即使残留，它也是可用的公共 DNS。改动前先把原值写进 `record.json`；主服务换了就先还原旧服务再设新的。
  断开、内核放弃重启、关闭占位或助手退出时还原；还原前当前值必须仍是占位地址，期间被别人改过就保留别人的设置。

### 配置生成

- 纯函数 `ProxyConfigBuilder.build(_:environment:)` 生成 JSON。JSON 是合法的 YAML，mihomo 直接读取。
  输出是确定的：键排序，数组按模型顺序。profile 有任何 `ProxyProblem` 时抛出 `ProxyInvalidProfile`，不生成配置。
- 固定项：`mode`（当前模式，见上）、`log-level: warning`、`ipv6: false`、`mixed-port`、`allow-lan`、`find-process-mode: strict`、
  `profile.store-selected`、`profile.store-fake-ip`、`unified-delay`、`tcp-concurrent`、`sniffer`（HTTP、TLS、QUIC）、
  `dns`、`tun`（仅 TUN 模式）、`proxy-providers`、`proxy-groups`、`rule-providers`、`rules`。
- 从不生成：TCP `external-controller`、`secret`、`external-ui`、`external-ui-url`、脚本。
- 命名：provider 为 `src-<来源 id 前 8 位>`；策略组用策略名称（唯一）；分流组为 `route/<分流 id>`（hidden）；
  规则集为 `geosite-<名称>`、`geoip-<名称>`，自定义规则集为 `custom-<id 前 8 位>-<序号>`。
- 策略组都写 `empty-fallback: REJECT`。mihomo 默认用 `COMPATIBLE` 顶替筛不出节点的组，而 `COMPATIBLE` 实际是直连，
  本该走代理的流量会直连出去。当前来源下没有任何 provider、也没有成员策略时，组内只放 `REJECT`；界面显示「没有节点」。
- 正则先用 `NSRegularExpression` 校验，且不能含反引号（mihomo 用它切分多条筛选）；配置在应用前再交给内核 `-t`
  校验，两者都通过才应用。mihomo 用 `regexp2.MustCompile` 编译组筛选，ICU 接受而 regexp2 不接受的正则
  （如占有量词）会让 `-t` panic、退出码 2。`-t` 会写 `cache.db`，所以在临时目录运行。
- 应用：首次启动写入文件。运行中用 `PUT /configs?force=true` 提交 payload，再按保存的分流选择逐个
  `PUT /proxies/route…`。

### 控制接口客户端

- HTTP/1.1，直接读写 Unix socket（用户态内核）或助手交来的 fd（助手内核）。请求编码与响应解析（Content-Length、
  chunked、按行的流）放在 `Model/` 里，由 harness 覆盖。
- 用到的接口：`/version`；`/configs`（GET、PUT、PATCH）；`/proxies`；`PUT /proxies/{name}`；
  `/proxies/{name}/delay`；`/group/{name}/delay`；`/providers/proxies`（含订阅信息）；
  `PUT /providers/proxies/{name}`；`/providers/rules`（规则数与更新时间）；`PUT /providers/rules/{name}`；
  `GET /connections`（活动页每秒轮询）、`DELETE /connections/{id}`；流式的 `/traffic`
  （概览与菜单栏的网速，只在需要显示时读取）、`/logs`（规则集更新；网址测试读 `?level=info` 里本次连接
  命中的规则与出口：HTTP CONNECT 先回 200 再拨号，所以只看连接快照拿不到拨号失败）。

### 内核更新

- **打包内核**：版本与各架构的 SHA-256 只写在 `Vendor/mihomo/core.env`。`Scripts/upgrade-mihomo.sh [版本]`
  从 GitHub API 读取发布信息，按发布页公布的 SHA-256（API 的 `digest`）校验两个架构的压缩包，用 `-v` 核对版本与架构，
  比对上游 LICENSE，改写 `core.env` 和 `NOTICE.md` 的版本，再跑 `Scripts/proxy-smoke.sh`；任何一步失败都还原。
  `--check` 只报告最新版本。
- **应用内更新**：设置 › 代理 › 通用 › 内核，用户点「检查更新」时才请求 GitHub，没有后台检查，也不自动安装。
  1. 读取 `releases/latest`：跳过草稿、预发布和不是 `vX.Y.Z` 的标签（Alpha 版不装）；按架构选资源，Intel 用
     `amd64-compatible`；没有 `sha256:` digest 的发布不安装。
  2. 下载用私有的 `.ephemeral`、`urlCache = nil` 会话。内核运行中时请求经混合端口，境内也能访问 GitHub。
  3. 先校验 SHA-256，再用 `Platform/Compression/Zlib` 解压，写入 `Proxy/Releases/.staging/`。`-v` 必须报告这个版本
     和本机架构，再用当前配置 `-t`；都通过才移到 `Proxy/Releases/<版本>/mihomo`。
  4. 已连接时立即换新内核重启。新内核起不来（退出或控制接口不可达）就删除它、重新启动之前的内核，并提示。
- **选择规则**：打包内核和已下载内核里版本最新的一个运行，版本相同时用打包内核（它有 Tinycast 的签名）。
  被取代的下载版本等选中的内核启动成功后才删除，新版本失败时还有退路。Tinycast 升级带来更新的打包内核后，
  不比它新的下载版本随之删除。「恢复内置版本」删除全部下载版本。没有打包内核的构建在连接时提示缺少内核，
  在这里下载一个即可。
- **验证**：`Scripts/proxy-smoke.sh` 让一个没有内核的包从本地发布源完成一次应用内安装；再用一个能通过 `-v`、`-t`
  但一启动就退出的假内核走完回退；digest 不符的下载被拒绝；最后恢复内置版本。

## 存储

- `~/Library/Application Support/<bundle id>/Proxy/profile.json`：启用状态、来源（不含链接）、策略、分流、
  我的规则、通用设置（含菜单栏图标），文档层另有是否保持连接与当前模式。原子写入；文件损坏时保留副本，回落到默认值。
  新增的键都按缺省值解码，旧文件不会被当成损坏。
- `Proxy/Core/`：用户态内核的工作目录（`-d`）：配置、provider 缓存、日志。
- `Proxy/Releases/<版本>/mihomo`：应用内下载的内核，放在内核工作目录之外。
- 钥匙串 scope `proxy-subscriptions`：订阅链接。
- 本地文件：用户选择的路径（能写成 `~` 相对路径时就这样存），或在 `Proxy/Nodes/` 下新建。
- 设置备份和 `settings.json` 都不包含代理的任何数据：启用代理会运行第三方内核并能接管整机流量，属于授予能力的开关；
  订阅链接是机密。因此不新增 `AppSettingsKey`，也就不进入 `SettingsBackupCoverage` 和 `SettingsFileSchema`。

## 界面

以[设计稿 v3](proxy-redesign/index.html)为准（2026-10-24 用户确认方向，D9–D12）。代理窗口照设置窗口的做法；
启动器、对话框、HUD、设置分组表单、编辑面板沿用现有组件，不引入新的视觉语言。

- **状态在前。** 菜单栏、代理窗口、启动器状态卡、设置都先给出连接状态、模式、出口节点与延迟。
- **代理窗口**（D9）：`ProxyCoordinator.showWindow(_:)` 打开；`AppWindowController` 承载 SwiftUI 的
  `NavigationSplitView`，`sceneBridgingOptions = [.toolbars, .title]`，`ProxyWindowChrome` 设定标题栏，与设置窗口相同。
  侧边栏五页，底部是连接状态与实时网速；工具栏是页面标题与副标题、当页操作、模式分段控件、连接开关。
  - **概览**：出口卡（默认策略经哪些成员策略到哪个节点、协议、来源、延迟与最近几次测速、「更换节点」）；流量卡
    （下载、上传、近 60 秒曲线、本次连接累计）；流向图（左列我的规则与各分类，中列策略，右列出口节点或直连、拒绝；
    线条用策略色，悬停高亮整条路径；点一类流量改它的去向，点策略或出口跳到节点页；非规则模式下所有线汇到一个出口）；
    状态卡（TUN、DNS 占位、规则集、主订阅用量）。没有来源时换成三步引导：添加节点、安装 TUN 助手、连接。
  - **节点**：策略标签（策略色圆点加当前出口的国旗）；所选策略的说明行（类型、当前出口与延迟、经过的成员策略、用于哪些分流）；
    节点卡片按地区分组（名称、协议、UDP、延迟着色），手动策略点卡片即切换，自动选择与故障转移只读并说明规则，故障转移
    标出顺序；「全部节点」标签是节点池，可按来源筛选。新建、编辑策略打开编辑面板。
  - **分流**：网址测试（由内核实际匹配）；我的规则（最先匹配）；按类别的分流（拖动排序、行尾开关、目标是带策略色与当前出口的
    弹出菜单）；「其他流量」固定在最后；规则集状态与「立即更新」「恢复推荐分流…」；「添加分流」打开规则库面板。
  - **订阅**：先说明订阅只提供节点；订阅卡片（节点数、更新时间、用量进度条、到期日与剩余天数、启用开关、更新、编辑、查看节点）；
    本地文件卡片（路径、在访达中显示、编辑）；添加卡片（粘贴订阅链接，或导入本地文件）。
  - **活动**（D11）：最近的连接（时间、目标、应用、命中的分流、策略与出口、流量），可按代理、直连、拒绝筛选和搜索；
    行上「＋」为这个域名或应用添加规则，匹配方式与目标在弹出框里选。只在页面可见时轮询。
- **菜单栏**（D12，默认关闭，设置里打开）：独立的状态项 `ProxyMenuBarController`（`NSStatusItem` 加 `NSMenu`），与日历的
  菜单栏项一样只放代理自己的操作。图标表示连接状态，可选附带下载速度。菜单：状态行（当前出口、延迟、经过的策略）、
  连接或断开、模式三选一、每个策略一个子菜单（手动策略列出成员策略与按地区再分一层的节点，延迟靠右着色；自动选择与
  故障转移只读）、全部测速、更新订阅、打开代理窗口（⌘O）、代理设置…（⌘,）。每次打开时按当前状态重建。
- **启动器**：状态卡三栏为出口节点与延迟、模式、连接（TUN 与连接时长）；回车在已连接时选择节点，否则连接。
  命令（设置页「代理」拥有，`SettingsTab.ownedCommands`）：选择节点、添加代理规则、连接代理、断开代理、规则模式、
  全局模式、直连模式、打开代理窗口、节点测速、更新订阅；连接与断开、三种模式都只列出当前适用的，热键都能绑。
  「代理分流」「代理策略」打开代理窗口的分流页与节点页。「选择节点」与「添加代理规则」的子屏保留；
  「添加代理规则」读取前台浏览器的网址，这是窗口做不到的。
- **设置 › 代理**：只留偏好：启用、打开代理窗口、连接（启动时连接、退出后保持连接、菜单栏图标与显示内容）、TUN 助手、DNS、
  订阅更新（间隔、经代理更新）、内核、高级（混合端口与终端命令、允许局域网、生成的配置、恢复默认设置）、命令。
  搜索到节点、策略、分流相关的词条时打开代理窗口的对应页。
- **编辑面板**：编辑订阅、本地文件、策略、我的规则、自定义规则集、添加分流、生成的配置。沿用设置的编辑面板
  （`SettingsEditorPresenter`，挂在代理窗口上）。文件选择面板挂成窗口的表单（sheet），窗口在全屏空间里时不会开到别的桌面。
- **视觉**：颜色留给策略。同一个策略在流向图的线条、节点卡片的选中框、分流目标、菜单圆点上是同一种颜色；延迟 150 ms 以下绿、
  以上橙、超时红、未测灰；其余用透明度色阶与语义色。
- **地区**：台湾不显示旗帜（中国大陆地区设置下系统把它画成缺字方框），用地球图标或只显示名称；匹配节点名时仍认旗帜。
  策略编辑只列出节点池里出现过的地区，其余收在「全部地区」里。占位提示都以「例如」开头，避免看起来像已填好的值。
- **对话框**：安装 TUN 助手、删除来源（写明会影响哪个策略的节点数）、删除策略、恢复推荐分流、恢复默认设置、恢复内置内核。
- **HUD**：切换结果、测速进度（全部测速可取消）、更新失败。

## 安全规则

1. root 进程只读写自己的目录，从不跟随 Tinycast 提供的路径；写入的文件名按白名单校验。
2. 助手校验客户端：安装时记录的代码签名身份（identifier 与叶证书）加 uid；Tinycast 也校验助手的签名身份。
3. 内核副本先复制后校验，校验的是 root 目录里的那份文件。只安装 MetaCubeX 官方发布包，以 GitHub 公布的 SHA-256 为准。
4. 控制 socket 只有 root 能连接，Tinycast 经 XPC 拿到 fd。
5. 不传脚本参数；生成的配置不含外部 UI、脚本和 TCP 控制接口。
6. 订阅链接不写日志、不出现在「生成的配置」预览里（替换为占位文字）、不进备份。
7. 卸载脚本删除 plist、二进制和 root 目录，并还原 DNS 备份。Tinycast 自己的卸载与清理功能能识别助手并给出提示。
8. 失败如实报告；用户取消授权不算失败。

## 验收

- **AC-1 首次连接**：添加订阅后一键连接（TUN）。浏览器、终端、UDP（DNS、QUIC）都经过代理；断开后网络恢复直连，DNS 还原。
- **AC-2 分流**：在推荐分流下，openai.com 走「AI 服务」选定的策略，baidu.com 直连，广告域名被拒绝。
  在代理窗口、菜单栏或启动器里给某个分流换策略、换节点、换模式后，新连接 1 秒内生效，不重载配置。
- **AC-3 合并**：两个订阅加一个本地文件合并后，节点池计数正确；取消勾选一个来源后它的节点消失；
  某个订阅更新失败时保留它上次的节点。
- **AC-4 策略**：按地区筛选的自动策略只含该地区的节点；新增订阅里同地区的节点自动纳入。
- **AC-5 我的规则**：新规则优先于所有分流；测试结果与内核实际匹配一致（以 `/connections` 的 rule 字段核对）。
- **AC-6 TUN 助手**：安装只弹一次管理员授权；非 Tinycast 进程连接助手被拒绝；卸载后没有残留（plist、二进制、目录、DNS 设置）。
- **AC-7 稳定性**：内核崩溃后自动重启，并恢复 TUN 和各项选择；开启「退出后保持连接」时退出 Tinycast 不断网；重新打开后状态一致。
- **AC-8 资源**：内核空闲常驻内存不超过 90 MB；Tinycast 主进程因代理功能增加的常驻内存不超过 15 MB；
  启动器打开代理子屏不慢于现有子屏。
- **AC-9 隐私**：订阅链接不出现在日志、预览、备份和 `settings.json` 中；配置文件权限为 0600。
- **AC-10 完成标准**：harness、lint（含 8 种语言的译文检查）、Debug 构建无新增警告、Model 纯度检查通过，文档同步更新。
- **AC-11 代理窗口**：五页内容与内核一致：出口与延迟、流向图与分流表、节点卡片的当前项；流量曲线每秒更新；
  关闭窗口或离开页面后不再读取 `/traffic`、`/connections`。没有来源时概览是三步引导，走完即连接。
- **AC-12 菜单栏**：默认不显示；打开后图标随连接状态变化；菜单里换模式、换节点后，窗口与启动器状态卡同步。
- **AC-13 活动**：列出的连接与内核一致（命中的规则、策略链）；给一条连接添加规则后，新连接按新规则走。
- **AC-14 规则库与链接**：规则库添加的分流能下载并命中；Loyalsoldier 的 `.txt`（YAML）、blackmatrix7 的 YAML 混合规则、
  SukkaW 的文本混合规则都能自动识别并生效；meta-rules-dat 里不存在的 geosite 名称在添加前被拒绝。
- **AC-15 地区**：常见机场命名（中文、英文、代码、城市、旗帜）归到正确地区；印度尼西亚不归为印度，罗马尼亚不归为意大利，
  「CN2 GIA」线路不归为中国大陆。

## 风险

| 风险 | 应对 |
| --- | --- |
| TUN 原生验收会中断当前网络：两个 TUN 不能同时运行，需要先退出 Clash Verge Rev，开发会话也可能断开 | P0 和 P3 的原生验收约定时间、由用户在场时进行；在此之前只用用户态内核验证 |
| 自签名下 XPC 签名校验和 fd 传递是否可行 | P0 先做最小原型验证；不可行时退回目录 ACL 方案，接受「同一用户的进程可控制内核」的风险并写入文档 |
| 首次下载规则集或订阅时网络不可达 | 规则集经默认策略下载；订阅可选经代理更新；P6 在安装包里放规则快照 |
| mihomo 升级带来配置变化 | 打包内核用 `upgrade-mihomo.sh` 升级，smoke 不过就还原；应用内更新先过 `-v`、`-t`，起不来自动回退，内置内核始终保留 |
| 局域网 DNS 绕过 TUN | DNS 占位，断开时还原 |
