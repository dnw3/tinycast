# Disk Cleanup

Finds caches, logs, build output, tool stores, idle project builds, personal files worth a second look,
leftovers of removed apps and stale macOS updates, and removes each the way its owner expects. A
palette screen lists them by category; Quick Clean and scheduled runs take only the audited safe rows;
Disk Usage shows where the space went. See the [Spec](../plans/cleanup-spec.md) and
[Plan](../plans/cleanup-plan.md); this document covers what is built.

## Invariants

- **`CleanupSafetyPolicy.evaluate` is the only gate.** Every leaf is evaluated when it is found and
  again immediately before it is removed. There is no removal path that skips it.
- **The catalog is an allowlist.** A path is offered only when it matches a catalog pattern exactly
  (`CleanupCatalog.resolve`), or when a discoverer's **evidence** for that exact path satisfies its
  target's policy, which the gate re-decides from the evidence and the runner re-reads before acting.
- **Inside home, with one exception.** Leftover macOS updates are the only removal outside home and
  the only one that asks for an administrator password; Tinycast holds no privileged helper.
- **Each owner's own way.** Tool stores are cleaned by the tool's command, iCloud Drive downloads are
  evicted rather than deleted, and personal files, leftovers and anything unrecognized go to the Trash.
- **Never-delete wins over every allow rule**, apart from the audited exceptions in
  `neverDeleteExceptions`, each pinned by `cleanup-test`. Deny rules are case-insensitive because
  APFS is; allow rules match exactly.
- **Safe means the owner rebuilds it without asking and you would not notice.** Only safe targets are
  preselected, deleted directly and taken by Quick Clean and scheduled runs. Everything else is a reviewed row that goes
  to the Trash. An unrecognized cache is listed, never hidden and never safe.
- **A symlinked ancestor refuses the leaf.** The caller hands the policy the resolved parent; if it is
  not the lexical parent under the resolved home, the leaf is refused rather than followed.
- **Volatile facts are re-read, never cached.** Whether an owning app or tool is running is part of
  each read of the selection, and the runner checks again before acting.
- **Tinycast's own folders, for every channel, are never offered.**
- **The Model is pure.** `Features/Cleanup/Model/` takes home, resolved paths, running apps and the
  clock as parameters, and `cleanup-test` compiles it verbatim.

## Layers

| File | Role |
| --- | --- |
| `Model/CleanupTarget.swift` | Categories, tiers, dispositions, deletion mode, `CleanupPattern`, `CleanupTarget` |
| `Model/CleanupCatalog.swift` | The audited targets, the reserved paths, `resolve`, cache classification |
| `Model/CleanupSafetyPolicy.swift` | `evaluate`, the never-delete and protected-name rules, running owners |
| `Model/CleanupPlan.swift` | Items, groups, the plan, the selection, exclusions |
| `Model/KeepNewestPolicy.swift` | Which version-named siblings to keep |
| `Model/CleanupNaming.swift` | Row titles derived from folder names |
| `Model/CleanupReport.swift` | The run's tallies and errno-mapped failures |
| `Model/CleanupProjectRules.swift` | The project rules: markers, artifact folder, lockfiles, state that refuses it |
| `Model/CleanupProjectPolicy.swift` | The evidence a project artifact is judged on, and the verdict |
| `Model/CleanupCloudPolicy.swift` | Which iCloud Drive downloads may lose their local copy |
| `Model/CleanupSchedule.swift` | When a scheduled run is due, the low-space crossing, the history list |
| `Model/DiskUsageLevel.swift` | The analyzer's entries for one folder, and what it may move to the Trash |
| `Model/CleanupFilePolicy.swift` | Personal files: the roots, the kinds, the duplicate keeper, the re-decision |
| `Model/CleanupLeftoverPolicy.swift` | Removed apps' data, dead launch agents, obsolete extensions, old CLI versions |
| `Model/CleanupSystemUpdatePolicy.swift` | Leftover macOS updates: the two folders, the evidence, the privileged script |
| `Model/CleanupTools.swift` | The tools Tinycast cleans by command, their fixed arguments, output parsers |
| `Service/CleanupAccess.swift` | **Impure.** Full Disk Access, running tools, free space, the scan environment |
| `Service/CleanupScanner.swift` | **Impure.** Expands patterns, `lstat`s each leaf and asks the policy |
| `Service/DiskUsageScanner.swift` | **Impure.** `getattrlistbulk` walks that size each leaf |
| `Service/CleanupRunner.swift` | **Impure.** Re-checks each item, then deletes, trashes or empties it |
| `Service/CleanupProjectScanner.swift` | **Impure.** Walks home for projects and reads each one's evidence |
| `Service/CleanupScheduleStore.swift` | **Impure.** The schedule's pump, the free-space watch, the run history |
| `Service/DiskUsageSession.swift` | **Impure.** The analyzer's open levels; lists a folder and streams its sizes |
| `Service/CleanupCloudScanner.swift` | **Impure.** Reads each iCloud file's download and upload state |
| `Service/CleanupFileScanner.swift` | **Impure.** Walks the personal folders, hashes duplicates, finds installers |
| `Service/CleanupLeftoverScanner.swift` | **Impure.** Reads what still owns each candidate: apps, launch jobs, LaunchServices |
| `Service/CleanupSystemUpdateScanner.swift` | **Impure.** Reads update leftovers' facts; runs the one privileged `rm` |
| `Service/CleanupToolScanner.swift` | **Impure.** Locates each tool, probes what it could free, runs its command |
| `Service/CleanupSession.swift` | One visit: the scan, the plan, the selection and the focused group |
| `Service/CleanupTarget+Localization.swift` | Titles, explanations and reasons |
| `UI/CleanupCoordinator.swift` | Every action; the confirmation lives here, not in the runner |
| `UI/CleanupScreen.swift` | Both modes, the footer and the ⌘K menu |
| `UI/CleanupList.swift`, `UI/CleanupDetail.swift` | The list and the right-hand pane |
| `UI/StorageBar.swift` | Used, selected and free space on the overview |
| `UI/DiskUsageCoordinator.swift`, `UI/DiskUsageScreen.swift`, `UI/DiskUsageList.swift` | The analyzer |
| `Settings/CleanupSettingsView.swift` | The Disk Cleanup pane |
| `Settings/CleanupSettingsStore.swift` | Deletion mode and excluded folders; neither enters a backup |

It reuses `PathFacts`, `UninstallProtectionRules` and the measured TCC prefix list from
`Uninstall/Model/UninstallProtection.swift`.

## Patterns and claims

A `CleanupPattern` is a home-relative path in which `*` matches one component. A `contentsOnly`
pattern names a folder whose children are removed and which is itself kept.

The two generic targets, recognized caches and other caches, share `Library/Caches/*` and each
container's `Data/Library/Caches`. A generic leaf is skipped when a specific target or a reserved
path claims it, which is how each byte is counted once: `Library/Caches/Google` belongs to Chrome,
`Library/Caches/JetBrains` to the editors, and `Library/Caches/Homebrew` to a later phase's
`brew cleanup`. A specific target also gives way to a deeper one, so `Logs/*` never lists
`Logs/DiagnosticReports`, which crash reports list file by file.

## The catalog

| Target | Where | Tier | Notes |
| --- | --- | --- | --- |
| App caches | `Library/Caches/*`, container caches | safe | names in `recognizedCaches`, or a `.ShipIt` suffix |
| Other app caches | same | review | everything unrecognized and unprotected |
| Logs | `Library/Logs/*` | safe | |
| Crash reports | `Library/Logs/DiagnosticReports/*` | safe | |
| Saved state | `Library/Saved Application State/*` | safe | untouched for 30 days |
| Device firmware | `Library/iTunes/* Software Updates/*` | safe | |
| Messages previews | `Library/Messages/Caches/Previews` | safe | emptied, never removed; needs Full Disk Access |
| Safari, Chromium browsers, Firefox | each browser's caches and per-profile GPU and code caches | safe | locked while the browser runs |
| Service workers | Chromium `Service Worker/{CacheStorage,ScriptCache}` | review | can hold a site's offline data |
| DerivedData | `Library/Developer/Xcode/DerivedData/*` | safe | locked while Xcode or `xcodebuild` runs |
| Xcode caches | Xcode's cache, documentation cache, XCTest devices, previews | safe | |
| Device support | `* DeviceSupport/*` | safe | the newest two per platform are kept |
| Archives | `Library/Developer/Xcode/Archives/*` | review | their dSYMs symbolicate shipped crashes |
| Simulator caches | `CoreSimulator/Caches`, Simulator's cache | safe | devices are left to `simctl` |
| Package caches | npm, Yarn, Bun, Deno, pip, uv, Poetry, Cargo, CocoaPods, RubyGems and others | safe | only cache folders, never installed tools |
| Package stores | Gradle, Maven, NuGet, Stack, Cabal, Bazel, Playwright, Puppeteer, Cypress | review | slow to restore or hold local builds |
| Editor caches | VS Code, Cursor, Zed, JetBrains | safe | never `LocalHistory` or `workspaceStorage` |
| Trash | `.Trash` | — | sized only; emptied through the system action |

### Refused, and why

- **Identity and account caches** (`com.apple.akd`, `accountsd`, CloudKit, FamilyCircle, the fragment
  list): wiping them makes the daemons re-authorize against the login keychain, which floods the
  user with password prompts. The fragment rule refuses a daemon nobody has listed yet.
- **System UI, search and fonts** (Finder, Dock, Control Center, Settings, Spotlight, FontRegistry,
  LaunchServices, icon services): panels go blank, search and font rendering break.
- **Endpoint security and MDM agents**: touching their files trips tamper detection.
- **Password managers, Screen Time and input methods**: vaults, parental controls and learned words.
- **JetBrains Application Support and `LocalHistory`, editor `workspaceStorage`, Poetry
  virtualenvs, Zed's database, Expo's login**: settings, history and environments, not caches.
- **Spotify, App Store state, E5RT, iCloud Drive state**: rebuildable, but a user can notice, so they
  are reviewed rather than safe.
- **Docker, Homebrew, Go, pnpm and simulator devices**: their own tools clean them correctly.

## Discovered sources

Only `.catalog` targets expand patterns. Every other `CleanupSource` is proposed by a discoverer,
which reads **evidence** and hands it to `evaluate` in `CleanupPathContext.evidence`; the gate decides
again from that evidence and refuses with `.evidenceMismatch` when it does not support the leaf or
the expected target. The runner re-reads the evidence from disk immediately before acting, so a scan's
evidence never authorizes a removal on its own.

### Projects

`CleanupProjectScanner` walks home to depth 6 (60,000 directories at most), skipping hidden folders,
`Library`, `Applications`, the media folders, packages and the artifact folders themselves, and keeps
every directory whose listing holds a rule's marker. Without Full Disk Access the TCC-guarded folders
are skipped. For each project it reads, once:

- **tracking** — `git ls-files` for the candidate folders, run with `core.fsmonitor=false`, hooks off,
  no system config and no optional locks, using a real git (never the `/usr/bin/git` shim, which offers
  to install the developer tools). A repository git cannot answer for hides its folders.
- **activity** — the newest modification of anything a person edits, skipping dependency trees, plus
  git's own index and HEAD. 20,000 entries at most; a walk that stops there proves nothing.
- **locks and state** — git's `index.lock`, and each rule's `refuseWhenPresent` (Terraform state).

`CleanupProjectPolicy.decide` offers a folder as **safe** only when the project is proven idle for
`cleanup.projectIdleDays` (30 by default), it has a lockfile, and the rule is not `alwaysReview`
(Unity, Unreal, CMake, .NET `bin`, Terraform); otherwise it is offered for review and goes to the
Trash. Tracked, recently edited, git-busy and state-holding folders are not offered at all. A process
whose working directory is inside the project locks its rows live (`CleanupLock.projectInUse`), read
from `proc_pidinfo` at scan time and again when a run starts.

Projects may live in `Documents`, `Desktop` or `Downloads`: the never-delete rule yields there for a
project's own artifact and nothing else. `Pictures`, `Music`, `Movies` and `Library` never hold one.

### Tool resources

Homebrew, pnpm, Go, Docker, simulators and Time Machine manage their own stores, so Tinycast never
deletes inside them — the catalog reserves their folders so no generic row can — and runs the tool's
own command instead (`CleanupDisposition.command`). Every one is **review**, never preselected and
never automatic.

| Row | Command | Size shown |
| --- | --- | --- |
| Homebrew Downloads | `brew cleanup --prune=all` | the cache folder, as an upper bound |
| Unavailable Simulators | `simctl delete unavailable` | the unavailable devices' folders |
| Unused pnpm Packages | `pnpm store prune` | the store, as an upper bound |
| Go Build Cache / Module Cache | `go clean -cache` / `-modcache` | `GOCACHE` / `GOMODCACHE` |
| Unused Docker Data | `docker system prune --force` — never `--volumes` | Docker's own reclaimable total |
| Old Local Snapshots | `tmutil deletelocalsnapshots <date>` for each, keeping the newest | unknown without root |

Arguments are fixed per tool in `CleanupTool.arguments`; the only variable is a snapshot date, which
must read `YYYY-MM-DD-HHMMSS`. Tools are found through the user's login shell (`ExecutableLocator`),
`simctl` through the selected developer directory and `tmutil` at its system path; each runs with stdin
closed and is terminated when the run is cancelled. A tool's running process locks its row, and a
non-zero exit is reported with the tail of its output. None of these needs administrator rights;
`tmutil` refusing a snapshot is reported like any other tool failure.

### Files

Everything here is the user's own, so every row is **review** and goes to the **Trash**, where it can
be put back; nothing is preselected and nothing is automatic. `CleanupFileScanner` walks `Downloads`,
`Desktop`, `Documents` and `Movies` (with Full Disk Access; they are TCC-guarded) to depth 10 and
300,000 entries, skipping hidden folders and anything inside a package or library. The never-delete
rule yields in those four roots only to a personal file's own evidence.

| Row | Rule |
| --- | --- |
| Installers | `.dmg`, `.pkg`, `.mpkg`, `.xip`, `.iso` |
| Unfinished Downloads | `.crdownload`, `.download`, `.part`, `.partial`, `.opdownload`, idle for a day |
| Duplicate Files | ≥ 10 MB, same length, same first megabyte, same SHA-256; the earliest-created copy is kept and never listed; 8 GB hashed at most |
| Large Files | at least `cleanup.largeFileThresholdMB` (1 GB by default) |
| Files Unused for a Year | ≥ 100 MB, not opened or changed for 365 days |
| macOS Installers | `/Applications/Install macOS *.app` whose bundle ID is `com.apple.InstallAssistant.*` |
| Local AI Models | `~/.ollama/models`, `~/.cache/huggingface/hub/*`, `~/.lmstudio/models/*/*` (catalog) |
| Virtual Machines | Parallels, VMware Fusion, VirtualBox and UTM machine folders (catalog) |
| iPhone and iPad Backups | `MobileSync/Backup/*`, an audited never-delete exception; named from `Info.plist`, the newest marked |

**iCloud Drive Downloads** are evicted, never deleted (`CleanupDisposition.evict`,
`FileManager.evictUbiquitousItem`): the file stays in iCloud and in Finder and downloads again on open.
Only a file of 20 MB or more that is current, fully uploaded, not uploading and without conflicts
qualifies, re-read before eviction. `Library/Mobile Documents` stays never-delete to everything else.

A file's size is its **private size** (`ATTR_CMNEXT_PRIVATESIZE`): what trashing that copy frees,
so an APFS clone reads as almost nothing, and clones are not offered as duplicates. The runner
re-reads a duplicate's keeper and digest before trashing it, so a copy changed after the scan is
refused.

### Leftovers

Offered only on positive evidence that nothing owns them, always **review**, always to the Trash: an
app installed somewhere unusual can look removed (Purge's OrbStack incident).

- **Removed apps' data** — a reverse-DNS folder (three components or more, never `com.apple.*`, never a
  protected identity name) in `Application Support`, `Containers`, `HTTPStorages` or `WebKit`, which
  LaunchServices has no app for, is not related at a dot boundary to any installed or running app or
  to any live launch job's label, and has not changed for 30 days. `Preferences` and `Group Containers`
  stay never-delete. A catalog row inside an offered folder is dropped, so nothing is counted twice.
- **Broken launch agents** — a `~/Library/LaunchAgents` plist whose absolute program is missing,
  outside `/usr`, `/bin`, `/sbin` and `/System`.
- **Obsolete editor extensions** — versions VS Code, VS Code Insiders, Cursor or Windsurf listed in their
  own `extensions/.obsolete`; locked while the editor runs.
- **Old CLI versions** — Claude Code's and Cursor agent's `versions/*`, keeping the one the
  `~/.local/bin` link targets, the newest, and any whose version can't be read; locked while it runs.

### Maintenance

Two commands owned by Settings › Disk Cleanup, each a single fixed program run without a shell:
**Rebuild Thumbnail Cache** (`qlmanage -r cache`) and **Restart Dock** (`killall Dock`).

### Leftover macOS updates

The one place outside home Tinycast removes from, and the one action that asks for an administrator
password. macOS stages an update in `/System/Volumes/Data/macOS Install Data` — the folder itself is
`sunlnk` and SIP-flagged, so only its contents (`UpdateBundle`, `index.sproduct`) are offered — and in
`/Library/Updates/<product>`. `Locked Files`, `index.plist` and `ProductMetadata.plist` are never
offered, nor anything SIP-restricted or `sunlnk`, nor a name outside `[A-Za-z0-9._-]`.

An item is a leftover only when it was last modified **before this Mac last booted** (an update
applies across a restart, so one staged since boot is still waiting) and `index.plist` lists no
pending product (for `/Library/Updates`, not that product). Measured on this Mac: 3.1 GB of
`UpdateBundle` from the update that installed 27.0.1.

`CleanupRunner` re-reads each item's evidence and re-evaluates it, then removes every approved path
in one `do shell script "/bin/rm -rf -- '…'" with prompt … with administrator privileges`, run through
`/usr/bin/osascript` so the main thread never blocks on the system prompt. The prompt's Cancel is
reported as cancelled; a path still present afterwards is reported as denied.

## Sizing

Sizes are **bytes on disk**, `ATTR_FILE_ALLOCSIZE` summed by a `getattrlistbulk` walk, because that is
what removing a folder gives back. Uninstall shows logical bytes, so the same folder can read
differently in the two screens. A hard-linked file counts once per walk, symlinks are never followed,
mount points are never entered, and each walk runs with
`IOPOL_MATERIALIZE_DATALESS_FILES_OFF` so it never downloads a dataless iCloud file. An unreadable
folder makes the total a floor (`isPartial`). Up to six walks run at once and their results reach
the main actor in batches at most ten times a second. Measured on a home directory of 165,000 files:
about three seconds and 6 MB peak. A whole phase-2 scan of this Mac without Full Disk Access — catalog,
tools, projects, leftovers and update files, then sizing — found 136 rows and 6.0 GB in 1.3 s, with a
59 MB peak resident size for the standalone probe process, runtime included. The Release
`Tinycast.app` measured 24.6 MB with Disk Cleanup in it.

Without Full Disk Access no scanner opens a TCC-guarded folder, the Trash, or the Files and Folders
set — Desktop, Documents, Downloads and iCloud Drive — nor any `.photoslibrary`, which asks for Photos
access wherever it lives, since that read is what raises the system's
privacy prompt (`CleanupScanner.isGuarded`). A fixed path there is listed locked, without a stat, and
sizing walks step around them.

## Running

`CleanupRunner.run` takes the confirmed items and, for each one, reads its facts again, re-evaluates
the policy with the same target expected, reclassifies its protection and re-checks running owners.
Any refusal becomes a reported failure. A `contentsOnly` item is emptied child by child, each child
evaluated on its own. Failures come from the POSIX code underneath, never from localized text, and an
item that is already gone counts as done. The file operations are injected, so
`cleanup-walk-test` observes a run without the real Trash.

## The screens

`Clean Up Disk` (`CommandID.cleanUpDisk`, owned by Settings › Disk Cleanup) opens `.cleanup`, laid out
like File Search: the list, a hairline, then the detail pane. `onScreenOpening` starts the scan; the
first row, Disk Overview, carries the reclaimable total in `Typography.readout`, a `StorageBar`
(used, selected, free; selected drawn at the trailing end of used) and per-category subtotals.
Without Full Disk Access an access row follows it, and on that row ↵ opens Privacy & Security
instead of cleaning. Groups are listed under their category headers in catalog order, and a size
stays blank until every walk in the group has landed, so no total reads low and nothing reorders.

A group with more than one item, or a generic one, drills into `.cleanupGroup` with →, ⌘I or a
double-click; ← or Esc pops back to the same group, since `CleanupSession.focusedGroupID` survives
the pop and `landingSelection` finds it. The group's items are sorted by size once, when it opens.

↵ always goes through `CleanupCoordinator.performCleanup`: it confirms with the deleted and trashed
byte counts, then checks that the plan's generation is unchanged and takes the selection that is
still checked and unlocked at that moment. The run shows `Cleaning…` in a cancellable HUD, removes
what it cleaned from the plan, and reports a summary or a notice listing up to five failures. While
it runs, `UpdateReadiness` holds an in-app update with `.cleaning`. Leaving both modes calls
`CleanupSession.leave()`, which cancels the scan and discards the plan; the next visit scans again.

## Quick Clean

`Quick Clean` (`CommandID.quickClean`) never opens the screen. It hides the palette, scans with a
cancellable `Looking for things to clean…` HUD, measures only safe delete-type items, and keeps what
`CleanupPlan.automaticItems` allows: audited, safe, deleted directly, unlocked and not excluded. A
confirmation states the total and the split, and the run then goes through the same `run` as the
screen, behind the same `isCleaning` gate; a screen run started while the dialog was open wins.

The Trash row is never selectable. Its ⌘K offers Empty Trash…, which hands over to the existing
`SystemAction.emptyTrash` and its own confirmation.

## Disk usage

`Disk Usage` (`CommandID.analyzeDiskUsage`) opens `.diskUsage` on the volume: home, `/Applications`,
`/Library`, and **System & Other** — the used space none of them explains — added once they are all
measured. → , ↵, ⌘I or a double-click opens a folder as another `.diskUsage` frame, so ← and Esc step
back with the parent's row still highlighted; `DiskUsageCoordinator.depth` is the number of analyzer
frames on the palette's back stack, and `DiskUsageSession` holds one level per frame — each level is
only its direct children, so memory never grows with the tree. Rows keep their listing order while
sizes stream in and sort largest first once, when the last one lands; each carries a bar for its share
of the folder. ⌘F shows in Finder, ⌃⌘C copies the path, and ⌃X moves an item to the Trash after a
confirmation — only inside home, below a top-level folder and outside `Library` (`DiskUsagePolicy`).
On a file ↵ shows it in Finder. The detail pane names no keys; it mentions the Trash only where
`DiskUsagePolicy` allows it, and the footer button carries the primary action.

Without Full Disk Access a guarded folder is a locked row that is never opened, ↵ on it opens the
setting, and every walk steps around the guarded folders (`DiskUsageScanner.measure(skipping:)`), so
totals that would have entered one read as floors. Leaving the mode discards every level.

## Automation

`CleanupScheduleStore` is started from `AppCore.start()` and follows `SupportReminderStore`'s pump: a
60-second startup delay, then a check every 15 minutes. It decides when; `CleanupCoordinator` cleans.

- **Scheduled cleaning** (`cleanupScheduleEnabled`) grants unattended deletion, so it is switched on
  only in Settings, after a Tinycast dialog listing every target it may take; it has no settings-file
  key and no backup (`settings-file-test` lists it with the other grants). The first run is a full
  interval (daily, weekly or monthly) after switching on. A due run waits until the Mac has been idle
  for five minutes (keys, clicks, scrolls and pointer moves), the palette is hidden, no dialog is open
  and nothing else is cleaning; it takes exactly what Quick Clean would — `automaticItems` — with no
  dialog, and reports in a HUD only when it removed something.
- **Low-space warning** — when free space (important-usage capacity) first drops below the threshold
  (10 GB by default), one HUD; while it stays below, the menu-bar menu has **Free Up Space… N left**.
- **History** — every run, manual or automatic, appends its tally (the newest 100 are kept) to
  `cleanup-schedule.json` in Application Support; the overview and Settings show the last run and
  the total freed.

## Preferences

**Deletion** chooses between deleting what its owner rebuilds (the default) and moving everything to
the Trash; `CleanupDeletionMode.resolve` turns every disposition into `.trash` in the second mode.
**Excluded Folders** subtract: an excluded path is skipped by the scanner and is never available to
the selection, and ⌘K › Don't Scan This adds one from a row and drops it from the current visit.
It is offered only on a single folder, since a many-item group's parent would hide its siblings.

## Tests

```sh
./Scripts/run-tests.sh cleanup-test
./Scripts/run-tests.sh cleanup-walk-test
```

`cleanup-walk-test` builds a scratch home under a UUID temporary directory: discovery against it,
allocated sizes with a hard link and an outward symlink, an unreadable folder, cancellation, batched
delivery, a run with recorded operations, a parent swapped for a symlink after the scan, and real
errno mapping.

Table-driven never-delete roots, path spellings, symlinked ancestors, protected names, the catalog
audit (every specific pattern round-trips to its own target, no reservation overlaps a target, tier
matches disposition), every recognized cache still resolving as recognized, running owners, the
selection invariants, streamed sizes, Quick Clean's eligibility, keep-newest, the deletion mode, the
report and naming.
