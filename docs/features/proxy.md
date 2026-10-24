# Proxy

A built-in proxy client: Tinycast runs the mihomo core itself, takes over the whole machine through TUN
when the TUN helper is installed, and otherwise offers a mixed port for tools set up by hand. Nodes,
strategies and routes are three separate layers, managed in the proxy window and switched from the menu
bar, the launcher and the window. See the [Spec](../plans/proxy-spec.md) and
[Plan](../plans/proxy-plan.md); this document covers what is built.

## Invariants

- **Sources contribute nodes only.** A subscription or node file never brings its own proxy groups or
  rules; strategies and routes are always the user's. A file's other content is reported as unused.
- **`ProxyConfigBuilder.build` is the only way to a config.** It is pure and deterministic, refuses any
  profile with a `ProxyProblem`, and a running core gets a new config only after `mihomo -t` accepts it.
  It never writes a TCP controller, a secret, an external UI or a script.
- **The core never routes on a guess.** Every strategy group carries `empty-fallback: REJECT`, so a
  group with no nodes rejects rather than going direct through mihomo's `COMPATIBLE` default.
- **Every source tests all its nodes.** Each provider carries a lazy `health-check` at the default URL,
  as often as the most eager automatic strategy on it asks, and a pool taking every node still names
  `ProxyConfigBuilder.everyNode`: mihomo merges the test filters of the groups on one source, so an
  empty one would leave the others' narrower filters in charge. After a connect or reload
  `ProxyManager` joins that first test, tests each node it failed once more (mihomo resets its DNS
  connections as the load ends, failing the lookups that first test has in flight), and drops each
  fastest-node strategy's cached pick.
- **Picks live in the profile and are applied again on every refresh.** A node pick or route target is
  saved first, then sent to the running core; `ProxyManager.applied` always reflects the last config so a
  later refresh cannot put an older pick back.
- **Mode is not part of the reload key.** Rule, Global and Direct switch through `PATCH /configs`, and
  `GLOBAL` is pinned to the default strategy.
- **Direct dials resolve at home.** `direct-nameserver` is the domestic DNS with
  `direct-nameserver-follow-policy: false`, so a direct route reaches local CDNs even for a domain the
  policy would resolve abroad.
- **Root stays small.** The TUN helper is a LaunchDaemon that only starts and stops the core it copied
  and verified, reads and writes its own directory, and restores the DNS placeholder it set.
- **A subscription link never leaves the Keychain** except in the config the core reads: it is masked in
  the generated-config viewer, never logged, and never carried by a settings backup.
- **Networked work uses `ProxyURLSession`**, a private `.ephemeral` session with no URL cache, routed
  through the mixed port only when the user asks.
- **A site test asks the core.** `ProxyProbe` reads the core's own log line for one test connection,
  and `ProxyProbe.highlight` maps it onto the flow map's rows; nothing guesses a match in the app.
- **The Model is pure.** `Features/Proxy/Model/` takes the clock, paths, rates and links as parameters,
  and the harnesses compile it verbatim.

## Layers

| Folder | Role |
| --- | --- |
| `Model/` | Profile, sources, strategies, routes, rules, regions, the rule catalog, config building, the controller API's wire types, flow and activity projections, probe parsing |
| `Service/` | `ProxyManager` (core lifecycle and reconcile), `ProxyStore`, the controller client, core download and install, traffic and connection monitors, the probe runner, localization of model titles |
| `Helper/` | `TinycastProxyHelper`: the root LaunchDaemon, its XPC endpoint, supervisor and DNS placeholder |
| `Window/` | The proxy window: root view, five panes, the flow map, editors that open over it |
| `Settings/` | Settings › Proxy (preferences only) and the editor panels the window reuses |
| `UI/` | `ProxyCoordinator`, the menu bar item, the launcher card and palette screens |

## Surfaces

- **Proxy window** (`ProxyWindowController`): Overview (exit, traffic, flow map with a site test that
  lights the path a site or address takes, status tiles, or a three-step guide with no source), Nodes
  (each strategy as a wrapping tag, region ones folded into one tag's menu; the strategy's summary, the
  strategies it can pick with region ones folded into one row, and its nodes in collapsible region
  groups; a manual strategy switches on click; New Strategy's menu makes one strategy per chosen region
  at once, `addRegionStrategies`, optionally offered by the default strategy; the node pool opens in a
  panel),
  Routing (my rules, routes with drag order, switches, rule-set status, and target menus listing the
  strategies, region ones in their own section under their flags, each with the node it reaches and its
  delay in a badge; every target picker in the editors lists them alike), Subscriptions
  (cards per source and an add card), Activity (live connections with filters, search and a rule for
  any row). Traffic and connections are read only while their page shows.
- **Menu bar** (`ProxyMenuBarController`, off by default): connect, the three modes, one submenu per
  strategy, each showing its node and delay, region ones folded into one Region Strategies submenu; a
  strategy's options group by region under each region's flag, open the window, test, update
  subscriptions when there are any, settings. Rebuilt each time it opens.
- **Launcher**: the status card (exit, mode, connection) and commands owned by Settings › Proxy, each
  listed only when it applies. Its target and node screens list region strategies in a section of
  their own, under their flags.
- **Settings › Proxy**: preferences only — the feature switch, the window, connection, menu bar, TUN,
  DNS, core, subscription updates, advanced and commands.

## Testing

`proxy-test` (model, config, regions, catalog, detection, flow, activity, probe), `proxy-api-test`,
`proxy-service-test`, `proxy-helper-test` and `proxy-smoke`, which drives the shipped manager against the
pinned core on loopback fixtures and checks that a later refresh keeps picks and route targets. See
[testing.md](../testing.md).
