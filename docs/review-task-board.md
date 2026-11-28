# Rayon Comprehensive Review, De-Wheeling & Optimization Task Board

> **Living Document Protocol (Mandatory for All Subagents)**
> Every subagent working on this initiative MUST read this document before starting, maintain only its assigned section (or update task checkboxes + commit SHAs in the Execution & QA logs), preserve every user-facing feature and setting (`AGENTS.md`), and verify changes before marking any item complete.

## Objectives

1. **Eliminate Settings Lag & UI/Animation Jank**
   - Diagnose and fix all causes of lag in Settings (including Ghostty terminal configuration, general preferences, sidebar switching, search, font/theme pickers).
   - Diagnose and fix all twitchy animations, layout jumps, non-native control quirks, and visual glitches across macOS and iOS (`apple-hig` + native SwiftUI/AppKit/UIKit semantics).
2. **Replace All Hand-Rolled Wheels with Mature Libraries / Native Frameworks**
   - Audit every target and package against Apple frameworks, `../FlowDown` dependencies, and mature Swift packages (`libghostty-spm`, `ConfigurableKit`, `AlertController`, `SPIndicator`, `WCDBSwift`, `Swift Charts`, `Runestone`, `BlossomColorPicker`, `Network.framework`, `CryptoKit`, `Compression`, etc.).
   - Remove unused legacy folders/packages and hand-rolled utilities wherever native or existing dependencies already solve the problem.
3. **Theoretical-Optimal Performance**
   - Eliminate main-thread stalls, redundant SwiftUI body evaluations, polling timers, O(N²) collection work, synchronous disk/keychain/font/config queries on render paths, lock contention, and unnecessary allocations across UI, Terminal, SSH, SFTP, Monitor, and Editor.
4. **Code Slimming (LOC Reduction without Feature Loss)**
   - Reduce code volume cleanly without removing any user-facing feature or setting.
   - Consolidate duplicated `+macOS` / `+iOS` logic where shared SwiftUI suffices.
5. **Abstraction, Over-Testing & Over-Defensiveness Cleanup**
   - Flatten single-use protocols, pass-through wrappers, and speculative indirections.
   - Prune tautological, mock-only, brittle, or redundant tests while keeping high-signal behavioral tests green.
   - Remove impossible defensive branches, multi-layer redundant validation, swallowed errors (`try?` hiding invariants), and dead compatibility shims.
6. **Atomic Git Commits, Prompt Pushes & Subagent `cua-driver` Sign-Off**
   - Every logical change lands as an atomic commit (`type(scope): Plain English sentence stating what is true after commit`), verified by `make build-macos`, `make build-ios`, `make test`, `make scan-license`, and `make check-localization`, then pushed promptly to `origin/main`.
   - Every wave of changes is verified inside the `rayon-qa` headless macOS VM via `Workflow/Scripts/qa-vm.sh` + `cua-driver` + performance benchmarks (`Bench+macOS.swift` & interactive timings) by a dedicated QA/Perf review subagent until zero issues remain.

---

## Master Checklist

- [x] **Phase 0**: Initialize shared task board (`docs/review-task-board.md`)
- [x] **Phase 1**: Parallel Deep Audit via Subagents
  - [x] **1A (`AUDIT-CUA-VM`)**: Live GUI walkthrough (`cua-driver` in `rayon-qa` VM) + baseline performance measurement (`Bench+macOS.swift`, Settings lag, UI/animation glitches)
  - [x] **1B (`AUDIT-UI-PERF`)**: Code-level Settings lag, SwiftUI animation/layout twitching, and theoretical-optimal performance audit
  - [x] **1C (`AUDIT-WHEELS`)**: Full inventory of remaining hand-rolled wheels vs Apple SDKs / `../FlowDown` / mature libraries
  - [x] **1D (`AUDIT-LOC-ABSTRACTIONS`)**: LOC slimming opportunities, over-abstraction, over-testing, and over-defensiveness audit
- [x] **Phase 2**: Synthesize Atomic Execution Backlog & Multi-Dimensional Reviewer Rubric
- [ ] **Phase 3**: Execute Atomic Refactoring & Optimization Waves (Subagents + Atomic Commit + Immediate Push per item)
- [ ] **Phase 4**: Independent Subagent `cua-driver` UI/UX + Performance + Code Review Loop (repeat fix -> commit -> push -> re-verify until 0 issues)

---

<!-- SECTION: AUDIT-CUA-VM -->
## 1A. Live UI, Animation & Performance Baseline (`cua-driver` + `rayon-qa` VM)

- Status: `COMPLETE`

### 1A.1 Test Environment & Build/Push Note for QA Subagents

- **Guest VM**: `rayon-qa` (`192.168.64.2`, headless macOS 26 guest, `1024×768 @ 1.0x` display, `cua-driver` daemon active with Accessibility + Screen Recording granted).
- **Important Build/Signing Requirement for `rayon-qa`**: Plain `make build-macos` signs with the host's `Apple Development` identity and embeds an iCloud provisioning profile (`Contents/embedded.provisionprofile`) whose device list does not include the `rayon-qa` VM UDID, causing `taskgated`/AMFI in the guest to kill `Rayon` immediately on launch. Always build for `rayon-qa` with ad-hoc signing (`CODE_SIGN_IDENTITY=- make build-macos`) before `Workflow/Scripts/qa-vm.sh push`, then register with `lsregister -f ~/Applications/Rayon.app` and set `defaults write me.mizorewww.rayon.debug licenseAgreed -bool true` for unattended `Bench` runs.
- **Artifacts Captured**: 49 window/desktop PNG screenshots + AX JSON snapshots in `/tmp/rayon-qa-audit.qMg8Q9/` and five `1 ms`-interval `sample` profiles (`/tmp/sample-*.txt` in guest).

---

### 1A.2 Baseline Quantitative Benchmarks (`Bench+macOS.swift` + Interactive `cua-driver`)

#### Table 1A.2a — Settings Benchmark (`RAYON_BENCH_SETTINGS=3`, Debug build, after 1 full warmup round across all 18 pages)

> `Bench.settle` measures cumulative main-RunLoop busy time inside a `400 ms` window (`200 ms` for `edit`). Any value near or above `400 ms` means the main thread was 100% saturated past the measurement window. Smooth 60/120 fps navigation requires `< 16 ms` (`< 8 ms` ideal).

| Operation / Settings Page | Median Main-Thread Busy | Max Main-Thread Busy | Interactive `cua-driver` AX Element Count | Notes |
| :--- | ---: | ---: | ---: | :--- |
| **`open settings` (cold window open)** | **435.72 ms** | **435.72 ms** | 66 | **Exceeds entire 400 ms settle window** (26+ dropped frames at 60 fps) |
| `page keyboard` | **176.10 ms** | **182.07 ms** | **91** | Slowest Settings page: 2-pass `Form`+`Table` height bounce + 38-item `Menu` per row |
| `page advanced` | **165.83 ms** | **172.73 ms** | 60 | Re-attaches `TerminalPreview` Metal surface after `keyboard` (`previews == false`) |
| `page colors` | **153.92 ms** | **156.24 ms** | 66 | Eager `BlossomColorPicker` instances + `TerminalPreview` |
| `page text/metrics` | **142.63 ms** | **147.41 ms** | — | 11 `LengthEditor` (`CommitField` + segmented `Picker`) rows in `.formStyle(.grouped)` |
| `page general` | **123.17 ms** | **127.47 ms** | 66 | Detaches `TerminalPreview`; builds 6 `SettingsGroup` sections |
| `page text` | **117.49 ms** | **118.41 ms** | 54 | Attaches `TerminalPreview` + `FontPicker` + sliders + 4 subpage links |
| `page colors/palette` (16 colors) | **114.44 ms** | **116.31 ms** | 113 | 16 live `BlossomColorPicker` + `CommitField` + reset buttons |
| `page cursor` | **112.31 ms** | **119.13 ms** | 64 | Segmented pickers + `LengthEditor`s + `BlossomColorPicker`s |
| `page input/mouse` | **104.70 ms** | **111.31 ms** | — | 11 rows (`PairEditor`, `FlagsEditor`, menus, toggles) |
| `page window` | **101.56 ms** | **110.19 ms** | 58 | Sliders + 2× `PairEditor` + popup picker |
| `page text/features` | **89.35 ms** | **89.87 ms** | 109 | 42+ OpenType feature button toggles across `RXFlowLayout`s |
| `page text/styles` | **84.51 ms** | **86.93 ms** | — | 3× `FontFamilyEditor` + 3× `FontStylePicker` + `FlagsEditor` |
| `page about` | **79.47 ms** | **80.97 ms** | 56 | Detaches `TerminalPreview`; sync `BuildInfo.plist` disk read |
| `page input` | **78.46 ms** | **79.05 ms** | 51 | 7 toggles + subpage link |
| `page connection` | **73.83 ms** | **74.80 ms** | 46 | SSH + UU Remote + Monitor groups |
| `page advanced/compatibility` | **67.86 ms** | **69.68 ms** | — | 5 rows |
| `page colors/find` | **59.49 ms** | **62.62 ms** | — | 4 `BlossomColorPicker` rows |
| `page text/glyphs` | **53.08 ms** | **53.10 ms** | — | Lightest subpage, still **> 3 frames** main-thread stall |
| `edit advanced` (`font-size` step, pre-debounce) | **20.74 ms** | **22.55 ms** | — | Single key edit re-evaluates & re-layouts entire page (> 16.6 ms frame budget!) |
| `edit text` (`font-size` step, pre-debounce) | **15.21 ms** | **18.57 ms** | — | Exceeds 16.6 ms frame budget on max |
| `edit keyboard` (`font-size` step, pre-debounce) | **13.97 ms** | **15.40 ms** | — | Re-runs `KeybindingList.rows()` even though `font-size` isn't on `Keyboard`! |
| `edit window` / `input` / `cursor` / `colors` | **8.29–12.51 ms** | **8.40–13.33 ms** | — | Measured inside `200 ms` window *before* `250 ms` `applyNow()` Ghostty reload + sync disk write fires |

#### Table 1A.2b — Heavy Interactive Settings Operations Observed via `cua-driver`

| Interactive Action in `rayon-qa` | Wall-Clock Round-Trip (`cua-driver`) | Post-Action `get_window_state` Latency | AX Elements | Observed Behavior |
| :--- | ---: | ---: | ---: | :--- |
| **Toggle `Show all 256 colors` (`Colors › Palette`)** | **1,556.7 ms** | 113.0 ms | 125 | **> 1.5 s UI stall** instantiating 256 `BlossomColorPicker` + 256 `CommitField` + 256 `Button` subtrees inside eager `Form(.grouped)` |
| **Open `Colors › Palette` subpage** | **1,447.8 ms** | — | 113 | Noticeable freeze before subpage appears |
| **Open `Text › Features and Variations` subpage** | **1,350.5 ms** | — | 109 | Multi-row `RXFlowLayout` double-measurement of 42+ toggle buttons |
| **Open `About › Libraries` push destination** | **1,235.2 ms** | — | 119 | Pushes `LibrariesView` onto `NavigationStack` |
| **Open `ThemeGallery` popover (633 themes)** | **1,070.3 ms** | 125.0 ms | 122 | Opens upward directly **over** the `Preview` terminal |
| **Open `FontPicker` popover** | **1,037.1 ms** | 133.3 ms | 69 | Instantiates CoreText custom fonts per row |
| **Settings Search (`query = "color"`)** | **1,050.3 ms** | **251.1 ms** | 96–120 | Eagerly mounts **all matching controls across 4 categories** (including `Palette` color pickers!) in one `Form` |

#### Table 1A.2c — Main Window Benchmarks (`RAYON_BENCH_SEED=1`: 200 servers / 10 folders / 49 identities / 100 snippets / 30 forwards)

| Benchmark Metric | Median Busy | Max Busy | Median Longest Unbroken Hang | Max Longest Unbroken Hang |
| :--- | ---: | ---: | ---: | ---: |
| **`enter home` (from `servers`, `n=5`)** | **254.44 ms** | **256.37 ms** | **240.50 ms** | **243.55 ms** |
| **`page monitor` (`n=3`)** | **409.11 ms** | **410.46 ms** | **339.02 ms** | **339.67 ms** |
| **`page servers` (`n=3`)** | **313.93 ms** | **348.94 ms** | **311.33 ms** | **346.56 ms** |
| **`page identities` (`n=3`)** | **271.93 ms** | **283.14 ms** | **264.16 ms** | **275.49 ms** |
| **`page desktops` (`n=3`)** | **218.76 ms** | **238.88 ms** | **217.24 ms** | **237.39 ms** |
| **`page forwards` (`n=3`)** | **213.95 ms** | **234.74 ms** | **211.86 ms** | **216.16 ms** |
| **`page files` (`n=3`)** | **197.02 ms** | **229.53 ms** | **174.86 ms** | **190.90 ms** |
| **`page terminal` (`n=3`)** | **163.96 ms** | **190.61 ms** | **122.75 ms** | **157.56 ms** |
| **`page snippets` (`n=3`)** | **154.80 ms** | **159.98 ms** | **116.36 ms** | **120.02 ms** |
| **`page dashboard` (`n=3`)** | **120.16 ms** | **134.98 ms** | **77.20 ms** | **91.27 ms** |
| **`page home` (`n=3`)** | **84.92 ms** | **92.16 ms** | **51.56 ms** | **57.06 ms** |
| `change on servers` (1-server `lastBanner` update) | **64.05 ms** | **88.91 ms** | — | — |
| `change on forwards` / `desktops` | **37.87 / 34.62 ms** | **39.35 / 34.79 ms** | — | — |
| `change on identities` / `snippets` / `files` / `terminal` / `dashboard` | **22.52–26.90 ms** | **24.33–32.95 ms** | — | — |
| `change on monitor` / `home` | **17.02 / 14.57 ms** | **19.19 / 16.38 ms** | — | — |
| `show 1000` SFTP files (`RAYON_BENCH_FILES=1000`) | **99.36 ms** | **99.36 ms** | — | — |
| `show 5000` SFTP files (`RAYON_BENCH_FILES=5000`) | **102.67 ms** | **102.67 ms** | — | — |

---

### 1A.3 Live `sample` (1 ms) Main-Thread Callstack Hotspots

1. **Settings Page Switching (`/tmp/sample-settings-switch.txt`, `1,327` active main-thread ms)**:
   - **46.7% (`620 ms`) in AppKit Constraint & Subtree Layout** (`-[NSWindow _layoutViewTree]` `486 ms` + `-[NSWindow updateConstraintsIfNeeded]` `134 ms`):
     - `248 ms` inside `ViewGraph.renderDisplayList` -> `DisplayList.ViewUpdater.updateInheritedView` tearing down and recreating AppKit `NSControl`s (`NSPopUpButton`, `NSSlider`, `NSSwitch`, `NSTextField`, `BlossomColorPicker`) because `SettingsView.swift:93` puts `.id(selected)` on an unvirtualized `.formStyle(.grouped)` `Form`.
     - `123 ms` (`62 ms` `-[NSTableView layout]` + `61 ms` `-[NSTableRowData _keepTopRowStableAtLeastOnce:andDoWorkUntilDone:]`) on `Keyboard` table creation/resize.
     - **`56 ms` (`25 ms` layout + `31 ms` constraints) directly inside `IdealWidthUpToProposal.sizeThatFits`** (`KeybindingEditor.swift:544`), which measures each row's 38-item `Menu` twice (`sizeThatFits(.unspecified)` + constrained proposal).
   - **41.9% (`556 ms`) in SwiftUI Graph Update** (`NSHostingView.beginTransaction` -> `ViewGraphRootValueUpdater._updateViewGraph` -> `AG::Subgraph::update` `515 ms`):
     - `254 ms` in recursive `StackLayout.UnmanagedImplementation.sizeChildrenGenerallyWithConcreteMajorProposal` / `placeChildren1` laying out every section and row of `.formStyle(.grouped)`.
     - `104 ms` in `AG::Graph::input_value_ref_slow` -> `DynamicPreferenceCombiner.value.getter` (`62 ms`).
   - **Continuous Background DisplayLink Tick (`ghostty_surface_draw` on `@MainActor`)**:
     - `SharedDisplayLink.deliver` -> `TerminalSurfaceCoordinator.tick()` -> `TerminalSurface.draw()` -> `ghostty_surface_draw` runs on `@MainActor` via `FrameDelivery.enqueue`. Notice `TerminalPreviewSlot` (`TerminalPreview.swift:45-75`) **never calls `terminal.setActive(false, focus: false)`** when switching to non-preview pages (`General`, `Connection`, `Keyboard`, `About`), when `DisclosureGroup` is collapsed, or when Settings is behind another window!
2. **Settings Single-Key Edit (`/tmp/sample-settings-edit.txt`, `1,094` active main-thread ms)**:
   - `594 ms` in `ViewGraphRootValueUpdater._updateViewGraph` (`369 ms` in `StackLayout` re-measuring every row on the page) + `500 ms` in `_layoutViewTree` / `updateConstraintsIfNeeded` (`260 ms` in `DisplayList.ViewUpdater.updateInheritedView`), empirically confirming that mutating a single key in `TerminalSettings.config` invalidates every control on the active Settings page.
3. **Main Window Route Switching (`/tmp/sample-pages-switch.txt`, `1,257` active main-thread ms)**:
   - `811 ms` in `-[NSWindow _layoutViewTree]` (`216 ms` in `-[NSTableRowData _keepTopRowStableAtLeastOnce:andDoWorkUntilDone:]` -> `155 ms` `-[NSIndexSet indexesWithOptions:passingTest:]`, plus `makeViewForTableColumn:row:`), `193 ms` in `updateConstraintsIfNeeded` (`101 ms` `_FlexFrameLayout.sizeThatFits`), and `158 ms` in `ViewGraphRootValueUpdater._updateViewGraph` (`AG::Subgraph::update`).
4. **AX Inspection / VoiceOver Stall on `Keyboard` & `Search` (`/tmp/sample-settings-search.txt`)**:
   - `187 ms` inside `_AXXMIGCopyMultipleAttributeValues` -> `-[NSTableView viewAtColumn:row:makeIfNecessary:]` -> `-[NSTableRowData rowViewAtRow:createIfNeeded:]` (`65 ms`), forcing AppKit to materialize offscreen table cell views whenever Accessibility queries the window.

---

### 1A.4 Live Visual, Animation, Layout & AX Defects Observed in `rayon-qa`

#### A. Settings Window Defects ("设置过于卡顿" + Visual Quirks)

- **[VM-UI-01] `P0` — Pinned `TerminalPreview` Eats 33% of Window Height, Misaligns Horizontally with `Form`, Never Pauses Rendering, and Jumps Viewport on Category Switch**
  - **Evidence**: `settings/03-text.png`, `settings/04-colors.png`, `settings/08-keyboard.png`, `settings/09-advanced.png` (`TerminalPreview.swift:50-75`, `SettingsView.swift:102`).
  - **Observed**:
    1. `Preview` is pinned outside the `Form` scroll view, consuming ~210 pt of the 640 pt window height so only ~340 pt remains for actual settings—slicing the bottom row/footer buttons (`Features and Variations` in `03-text.png`; `Import from Ghostty…` / `Reset All Terminal Settings…` / `Restore Defaults…` sliced horizontally in half in `09-advanced.png`!).
    2. `Preview` uses `.padding([.horizontal, .top])` (16 pt), whereas macOS 26 `Form(.grouped)` insets cards by 20 pt—so the dark `Preview` box visibly juts out wider than every `Form` section card below it on both left and right edges.
    3. Switching `Text` -> `Keyboard` -> `Advanced` (`previews: true -> false -> true`) tears down and re-attaches the Metal `AppTerminalView`, jumping the form origin by ~210 pt.
    4. Line 6 of `TerminalPreview.sample` (`┌──┬──┐`) renders with a visible broken horizontal gap before `┐` (`┌──┬── ┐`) in the built-in font at default settings.
- **[VM-UI-02] `P1` — `Keyboard` Page Has TWO Duplicate `Restore Defaults…` Buttons + Unstyled Bright-White Table Header Corner Artifact**
  - **Evidence**: `settings/08-keyboard.png`, `settings/18-keyboard-minsize-720x480.png` (`CategoryPage.swift:51-60`, `KeybindingEditor.swift:300-345`).
  - **Observed**:
    1. One `Restore Defaults…` button sits at `y ≈ 285` under the 1-row `Option Key` form, and a **second `Restore Defaults…` button** sits at `y ≈ 615` in the `KeybindingList` bottom bar on the exact same page!
    2. Because `Table` uses `.scrollContentBackground(.hidden)` over `RXWindowBackground`, AppKit's `NSTableHeaderView` scroller corner draws an opaque **stark white rectangle** sticking out at the top-right edge of the table header above the scrollbar.
    3. Alternating `Table` rows draw stark white bars containing grey `Menu` capsules (`Copy ⌄`), creating double-nested pill chrome.
- **[VM-UI-03] `P1` — `FontPicker` Popover Inherits `.trailing` Text Alignment from `Form` (`Search fonts` Right-Aligned!) & Mixes Glass Header with Stark White `List`**
  - **Evidence**: `settings/11-font-picker-popover-win.png` (`FontEditors.swift:30-77`).
  - **Observed**: Inside `FontPicker`'s popover, the `Search fonts` placeholder/text in `TextField` is **right-aligned against the right edge of the search box** (inherited from macOS `Form` `LabeledContent` trailing column alignment), and the `List` below `Monospaced fonts only` lacks `.scrollContentBackground(.hidden)`, rendering a stark white box (70% empty below `PT Mono`) inside a translucent Liquid Glass popover frame where the dark terminal bleeds through the top header.
- **[VM-UI-04] `P1` — `ThemeGallery` Popover Opens Directly Over `Preview`, Blocking Live Theme Previewing**
  - **Evidence**: `settings/13-theme-gallery-popover-win.png` (`ThemeEditor.swift:109-154`).
  - **Observed**: `ThemeChoice` sits right below `Preview`, so `.popover` opens upward (`preferredArrowEdge` unset) and covers **85% of the `Preview` terminal**, defeating the live preview while browsing 633 themes.
- **[VM-UI-05] `P1` — Borderless `CommitField`s (`#ffffff`, `Default`, `Left 2 / Right 2`), Active `Thickening amount` When `Thicken strokes` Is Off, and Floating `No Theme` Row**
  - **Evidence**: `settings/03-text.png`, `settings/04-colors.png`, `settings/05-cursor.png`, `settings/06-window.png` (`ColorControl.swift:33, 96-130`, `SettingControl.swift:376-445`, `ThemeEditor.swift:61-84`).
  - **Observed**:
    1. In macOS `Form(.grouped)`, `TextField` inside `CommitField` draws **no border or field background**, so editable hex codes (`#ffffff`), lengths (`Default`), and paddings (`Left 2   [🔗]  Right 2`) look like stray static labels floating in empty grey space, and `Horizontal padding` vs `Vertical padding` `[🔗]` buttons fail to align vertically (`06-window.png`).
    2. On `Text` (`03-text.png`), `Thicken strokes` is OFF, yet `Thickening amount` (`255`, *"while thickening is on"*) remains fully enabled/undimmed.
    3. On `Colors` (`04-colors.png`), `Color theme` has no control on its title row while `No Theme` floats alone on a third row beneath `Separate themes for light and dark appearance`.
- **[VM-UI-06] `P1` — Double Search Bars on `About › Libraries` & Empty Phantom Sidebar `AXRow` Above `About`**
  - **Evidence**: `settings/16-about-libraries.png`, `settings/17-search-color.png`, `settings/01-settings-search-results.png` (`SettingsView.swift:78-83, 116, 123, 255-258`, `SettingsGroup.swift:89`).
  - **Observed**:
    1. Pushing `LibrariesView` displays **two simultaneous search bars** in the Settings window (`🔍 Search` in the sidebar AND `🔍 Search libraries` in the toolbar).
    2. `SettingsSection(title: nil, pages: [.about])` (`SettingsGroup.swift:89`) emits an empty selectable/focusable phantom `AXRow` (`[15] AXRow` with zero children) between `Advanced` and `About` in the sidebar `AXOutline`.
    3. In `SettingsSearchResults` (`final/01-settings-search-results.png`), each `Show <Category>` button is wrapped in its own `Section`, rendering a small grey button inside a full-width mostly-empty grouped form card.
- **[VM-UI-07] `P2` — Settings Window Restores at Launch in Front of Main Window While Inactive**
  - **Evidence**: `settings/11-font-picker-popover.png` (`SettingsWindow+macOS.swift:18-28`).
  - **Observed**: If Settings was open on quit, macOS scene restoration reopens `SettingsWindow` at cold launch visually stacked *in front of* the `Rayon` main window (`z_index` in front) while `Rayon` main window holds `keyWindow` (colored traffic lights behind, greyed-out inactive Settings window covering it in front), and initializes `TerminalPreview`'s Ghostty surface at launch.

#### B. Main Window, Sheets, Sessions & Animation Defects ("动画抽搐，UI很诡异")

- **[VM-UI-08] `P0` — Opening Terminal `Snippets` Drawer Injects a Search Bar into the Main Window Toolbar, Shoving Toolbar Buttons ~250 pt Sideways**
  - **Evidence**: `main/17-terminal-find-bar.png` vs `main/18-terminal-find-and-snippets.png` (`TerminalPage+macOS.swift:101-107, 876`).
  - **Observed**: Clicking `Snippets` (`</>`) slides in the right-hand drawer AND simultaneously triggers `.searchable` toolbar hoisting, dynamically inserting `🔍 Filter snippets` into the window's top-right `NSToolbar` and violently shifting the `A | A | ×` toolbar island ~250 pt to the left (and jumping it ~250 pt back right on close).
- **[VM-UI-09] `P0` — Three Incompatible Modal Sheet Design Systems + Clipped Content / Giant Empty Voids / Double Bottom-Corner Borders**
  - **Evidence**: `main/07-new-server-sheet.png`, `main/09-new-identity-sheet.png`, `main/11-new-snippet-sheet.png` vs `main/13-new-port-forward-sheet.png` vs `KeybindingEditor.swift:376` (`EditorForm.swift:63-73`, `Page.swift:182-217`).
  - **Observed**:
    1. `New Server`, `New Identity`, and `New Snippet` use `.editorSheet` (centered small bold header, borderless mid-row `Form` fields, `Cancel` next to `Add` on bottom-right), whereas `New Port Forward`, `Sign In`, `Open File`, and `What's Sent` use `SheetScaffold` (left-aligned large title, `ALL CAPS` labels, bordered fields, `Cancel` on far-left, custom capsule buttons), and `KeybindingBuilder` uses `NavigationStack` inside a sheet!
    2. `.editorSheet`'s hardcoded `.frame(minHeight: 360, idealHeight: 620)` leaves a **~180 pt blank white void** in `New Identity` (`09-new-identity-sheet.png`), yet **clips `New Server` mid-sentence** (`07-new-server-sheet.png`: `Folder`, `SFTP start folder`, and `Add and Connect` hidden below a scrollbar), and draws a visible **double rounded border artifact** at both bottom corners where the `.toolbar` footer bar meets the sheet corner mask.
- **[VM-UI-10] `P1` — `Servers` and `Files` Tables Overflow Horizontally at Default (`1024×678`) and Minimum (`940×600`) Window Sizes, Clipping `Tools` Buttons and Timestamps**
  - **Evidence**: `main/06-servers-table.png`, `main/06b-servers-minsize-940x600.png`, `extra/01-files-preview.png` (`ServersView+macOS.swift:173-249`, `FileTable+macOS.swift`).
  - **Observed**:
    1. On `Servers` at `1024×678`, a dark horizontal scrollbar overlays the bottom row (`server-150`) while `Address` already truncates (`203.0...71:2222`); at `940×600` (`MainWindow.minimumSize`), the `Files`, `Monitor`, and `Desktop` icon buttons in `Tools` are **completely clipped off-screen**!
    2. On `Files` (`01-files-preview.png`) at `1024×678`, `Table` shows a full-width horizontal scrollbar while simultaneously truncating `Name` and `Modified` (`21 Jun 2026 at 1:26 P...`), and its toolbar overflows so `Search` collapses into an icon circle.
    3. `Servers`, `Identities` (`08-identities-table.png`), and `Port Forward` (`12-port-forward-table.png`) render raw unclipped **sharp 90°-corner white `Table` rectangles** directly against the rounded grey window background (unlike `Files` and `Editor` which wrap content in rounded card chrome, though `Files`'s inner `Table` header still pokes square top corners into the rounded card).
- **[VM-UI-11] `P1` — Blank / Nameless Sidebar Row Under `Sessions` When Server Is Not in `RayonStore`**
  - **Evidence**: `extra/01-files-preview.png`, `extra/02-editor-preview.png` (`SidebarView+macOS.swift:247-251`).
  - **Observed**: `OwnerSidebarRow.title` resolves `.server(id)` via `(store.machine(id) ?? RDMachine()).name` without falling back to the open `FileTransferContext` / `EditorWorkspace` / `MonitorSession` / `RemoteDesktopSession` `machine.name`, rendering a **completely blank selected row** (`[🖧          📁 ✏️]`) in the sidebar!
- **[VM-UI-12] `P1` — Main Window Hand-Rolled Sidebar Lacks `AXOutline` Semantics, Keyboard Arrow Navigation, and Visual Parity with Settings Sidebar**
  - **Evidence**: `main-initial.png`, `main-initial.json` vs `settings-text.png`, `settings-text.json` (`SidebarView+macOS.swift:52-170`).
  - **Observed**: Main sidebar is a `ScrollView` of plain `AXButton`s (`[1] AXButton (Home)` .. `[7] AXButton (Remote Desktop, 40)`) with purple-tinted icons, zero `AXOutline`/`AXRow` roles, and no `↑`/`↓` keyboard navigation—whereas Settings uses native `List(.sidebar)` with monochrome icons and `AXOutline`.
- **[VM-UI-13] `P1` — Inconsistent Button Bars Across `Dashboard` Server Tiles & Tight `"Run..."` Pill on `Snippets`**
  - **Evidence**: `main/05-dashboard.png`, `main/10-snippets-grid.png` (`DashboardView+macOS.swift:165-168`, `SnippetsView.swift:141-143`).
  - **Observed**: On `Dashboard`, tiles without VNC show labeled pills `[>_ Terminal] [📁 Files] [⏱ Monitor]`, while `server-005` (with VNC) switches to bare borderless icons `[>_ Terminal] 📁 ⏱ 🖥` right beside labeled tiles, making grid rows look visually broken. On `Snippets`, every card's `Run…` pill renders tight against `⋯`.
- **[VM-UI-14] `P1` — Remote Desktop Stage Repeats `"Connecting"` Four Times & Terminal Split Shows Dual Cursors + Stark White Find Bar**
  - **Evidence**: `main/15b-remote-desktop-session.png`, `main/17-terminal-find-bar.png`, `main/19-terminal-split-panes.png`, `main/20-terminal-sidebar-collapsed.png` (`RemoteDesktopPage+macOS.swift`, `TerminalPage+macOS.swift:486-541`).
  - **Observed**:
    1. `RemoteDesktopPage` displays `🟣 Connecting | Connecting...` in the top control bar AND `Connecting` / `Connecting...` in the center of the black viewport (4× `"Connecting"` simultaneously).
    2. `TerminalPage`'s `searchBar` renders an unthemed bright white bar directly atop the dark `#282c34` terminal surface; splitting panes (`19-terminal-split-panes.png`) reflows the shell prompt twice across 3 lines in `Pane 1`, truncates `Pane 2 · Local Termi...`, and leaves visible block cursors in both panes (`20-terminal-sidebar-collapsed.png`).
- **[VM-UI-15] `P2` — Home Vertical Scrollbar Overflow When `TelemetryNoticeCard` Shows, Duplicate `"OK"` AX Label on Close (`×`), and Auto-Focus Ring on Menu-Bar Popover**
  - **Evidence**: `main-initial.png`, `main-initial.json`, `final/02-menubar-popover-desktop.png` (`HomeView+macOS.swift:20-35`, `DiagnosticsSettings.swift:274`, `MenubarTool.swift`).
  - **Observed**:
    1. On initial launch (`1024×678`), `TelemetryNoticeCard` pushes `HomeView`'s `minHeight: proxy.size.height` + safe-area inset over the viewport height, showing a full-height vertical scrollbar on Home (`main-initial.png`), and its `×` dismiss button sets `.accessibilityLabel("OK")`, creating two `AXButton (OK)` elements (`[13]` and `[15]`) in the same card.
    2. Opening the menu-bar monitor popover (`02-menubar-popover-desktop.png`) immediately draws a thick circular purple focus ring around the first header icon button (`Open Terminal`).

<!-- END SECTION: AUDIT-CUA-VM -->

---

<!-- SECTION: AUDIT-UI-PERF -->
## 1B. Settings Lag, Animation Jank & Theoretical Performance Audit

- Status: `COMPLETE`

---

### 1B.1 Focus Area 1 — Why Settings Is So Laggy ("设置过于卡顿")

#### [UI-PERF-01] `P0` — Monolithic `@Observable` Dictionary Invalidation Storm on Every Slider / Stepper / Toggle Tick
- **Locations**:
  - `Foundation/RayonTerminal/Sources/RayonTerminal/Settings/TerminalSettings.swift:8-21, 109-138, 161-178`
  - `Foundation/RayonTerminal/Sources/RayonTerminal/Settings/Views/SettingControl.swift:83, 92, 140, 170, 174, 180-185`
  - `Foundation/RayonTerminal/Sources/RayonTerminal/Settings/Views/CategoryPage.swift:79, 159`
  - `Foundation/RayonTerminal/Sources/RayonTerminal/Settings/Views/TerminalSettingsParts.swift:202`
- **Root Cause**:
  - `TerminalSettings` is `@Observable` and stores every Ghostty setting in a single monolithic `private(set) var config: [String: [String]]` (`TerminalSettings.swift:18`).
  - Swift Observation tracks `TerminalSettings.config` as a single property. Every `SettingRow` (`SettingControl.swift:92, 140`), every `SettingControl` (`SettingControl.swift:174`), every `ColorControl`, `SubpageLinks` (`CategoryPage.swift:79`), `RestoreDefaults` (`CategoryPage.swift:159`), and `TerminalSettingsUndoButtons` (`TerminalSettingsParts.swift:202`) reads `settings.config` (via `isSet`, `value`, `values`, `effectiveColor`).
  - Dragging **any** slider (`background-opacity`, `cursor-opacity`, `minimum-contrast`, `faint-opacity`, `font-thicken-strength`, `font-variation`) or clicking a stepper (`font-size`) mutates `config` at 60–120 Hz, invalidating **every single row and control on the visible Settings page** and triggering full AppKit `NSForm`/`NSTableView` cell re-measurement on every drag tick (the exact path measured by `Bench.settings` `"edit <id>"` in `Application/Rayon/Application/Bench+macOS.swift:140-150`).
- **Complexity (`Current` vs `Optimal`)**:
  - **Current**: $O(R)$ view body evaluations + $O(R)$ AppKit/UIKit form cell layout passes per drag tick ($R \approx 15\text{–}260$ controls).
  - **Optimal**: $O(1)$ — **only the 1 edited control** (and its row's reset indicator when `isSet` flips between `false` and `true`) re-evaluates.
- **Exact Fix (100% Feature Parity)**:
  1. Introduce fine-grained per-key `@Observable` slots inside `TerminalSettings`: e.g., `final class SettingSlot { var values: [String]? }` keyed by `SettingKey` ID in a fixed `[String: SettingSlot]` dictionary initialized once from `SettingCatalog.all` (plus a separate `extraSlots` map for custom/repeatable keys and per-group `modifiedCount: Int` slots for `SubpageLinks` / `RestoreDefaults`).
  2. Route `values(_:)`, `value(_:)`, `isSet(_:)`, and `set(_:values:)` through `slot(for: id).values` so Swift Observation subscribes each `SettingControl` / `SettingRow` **only** to its own `SettingSlot` (plus `theme` slot for `ColorControl` fallback colors).
  3. Bind continuous `Slider` controls (`SettingControl.swift:180-185`, `FontEditors.swift:256-265`) to a local `@State private var draftValue: Double?` while dragging or coalesce `TerminalSettings.scheduleApply()` while keeping per-slot UI updates $O(1)$.

---

#### [UI-PERF-02] `P0` — Eager `Form(.grouped)` Instantiation of `BlossomColorPicker`s (up to 256×), 38-Item Nested Action `Menu`s, `NSViewRepresentable` Recorders & Unbounded Search Results
- **Locations**:
  - `Application/Rayon/Interface/Settings/SettingsView.swift:92-99, 253-279`
  - `Foundation/RayonTerminal/Sources/RayonTerminal/Settings/Views/CategoryPage.swift:34-60, 171-172, 224-233`
  - `Foundation/RayonTerminal/Sources/RayonTerminal/Settings/Views/ColorControl.swift:31-48`
  - `Foundation/RayonTerminal/Sources/RayonTerminal/Settings/Views/ThemeEditor.swift:199-245`
  - `Foundation/RayonTerminal/Sources/RayonTerminal/Settings/Views/KeybindingEditor.swift:56-103, 175-217, 267-297`
  - `Foundation/RayonTerminal/Sources/RayonTerminal/Settings/Views/ShortcutRecorder.swift:46-56`
  - `Foundation/RayonTerminal/Sources/RayonTerminal/Settings/Views/FontEditors.swift:188-231`
  - `Foundation/RayonTerminal/Sources/RayonTerminal/Settings/Catalog/SettingCatalog.swift:95-100`
- **Root Cause**:
  1. **Page teardown + eager `Form(.grouped)` rebuild (`SettingsView.swift:93`)**: `.id(selected)` destroys and recreates the entire `Form` hierarchy on every sidebar click; macOS `Form(.grouped)` eagerly instantiates and measures all child views across all sections on appear.
  2. **16–256 live `BlossomColorPicker`s (`ColorControl.swift:36-46`, `ThemeEditor.swift:209-225`)**: Every color row and every `PaletteCell` mounts a full `BlossomColorPicker` with `.id(effective)`. Inside `Form(.grouped)`, `LazyVGrid` receives unbounded vertical height proposal from the outer form row, defeating laziness so toggling "All 256 Colors" instantiates **256 `BlossomColorPicker` + 256 `CommitField` + 256 `Button` subtrees** synchronously on the main thread.
  3. **Keyboard table row explosion (`CategoryPage.swift:51-60`, `KeybindingEditor.swift:72-97, 175-217`)**:
     - `CategoryPage` stacks a `.scrollDisabled(true)` `Form` measured via `.onScrollGeometryChange(for: CGFloat.self, of: \.contentSize.height)` -> `@State formHeight` above a `Table`, forcing a **2-pass layout bounce** on open.
     - Every visible `KeybindingList` row eagerly builds a nested `Menu` containing **all ~38 binding actions across 8 sections** wrapped in `IdealWidthUpToProposal` (`Layout` calling `subview.sizeThatFits` twice per row) AND unconditionally mounts `KeyRecorder` (`NSViewRepresentable`) even when `isRecording == false` (`ShortcutRecorder.swift:48`).
     - In **Settings Search** (`CategoryPage.swift:171-172`), matching *any* keyboard setting embeds the **entire ~40-row `KeybindingList`** directly inside the search `Form`!
  4. **Zero debounce on 1st search keystroke + per-keystroke regex (`SettingsView.swift:273`, `SettingCatalog.swift:95-100`)**:
     - `if found != nil { try? await Task.sleep(for: .milliseconds(150)) }` skips debounce when `found == nil`, so typing the very first character (e.g. `"c"` or `"a"`) synchronously runs `Found(query)` and builds **60–80+ interactive `SettingRow`s** in one frame.
     - `SettingDefinition.plainHelp` (`SettingCatalog.swift:98`) runs `replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)` on **every catalog entry on every search** (`CategoryPage.swift:227`).
  5. **$O(F \times E)$ repeated feature parsing inside `FontFeatureEditor.body` (`FontEditors.swift:188-231`)**: Calls `Self.parse($0)` inside `state(of:)` for each of the 42+ OpenType feature toggles inside multiple `RXFlowLayout`s (`Layout.swift:38-85`, which already measures every child twice).
- **Complexity (`Current` vs `Optimal`)**:
  - **Current**: $O(P \cdot C_{\text{heavy}})$ eager view/NSView creation per page switch ($256$ color pickers or $40 \times 38$ menu items + $40$ `NSView`s); $O(K \cdot \text{regex}) + O(M_{\text{matches}})$ synchronous first-keystroke search.
  - **Optimal**: $O(V)$ lightweight visible cells only; $O(1)$ pre-indexed lowercase search string lookup; lazy popovers on click.
- **Exact Fix (100% Feature Parity)**:
  1. **Lightweight Color Swatch + Lazy Popover**: Replace inline `BlossomColorPicker` in `ColorControl` (`ColorControl.swift:36-46`) and `PaletteEditor` (`ThemeEditor.swift:215`) with a lightweight native color swatch `Button` (`Circle` / `RoundedRectangle` filled with `Color(effective)`) that opens `BlossomColorPicker` inside `.popover` **only when clicked**. Keep `PaletteEditor` 256-color grid in a bounded scroll container or `DisclosureGroup` of 16-color blocks so `LazyVGrid` stays genuinely lazy.
  2. **Keyboard Page & Recorder Laziness**:
     - Mount `KeyRecorder` (`ShortcutRecorder.swift:48`) **only** when `isRecording == true`.
     - Replace the per-row 38-item nested `Menu` + `IdealWidthUpToProposal` with a lightweight button showing `entry.actionTitle` that opens a single shared popover/picker on click.
     - Replace the `.scrollDisabled(true)` `Form` + `onScrollGeometryChange` height-measurement hack (`CategoryPage.swift:51-57`) with a compact header bar above `Table` for `macos-option-as-alt`.
     - In `TerminalSettingsSearchSections` (`CategoryPage.swift:171-172`), render only matching shortcut rows (or a navigation link row to `Keyboard`) instead of embedding the entire 40-row `KeybindingList`.
  3. **Search Pre-Indexing & Debounce**: Precompute `plainHelp` and a single lowercased `searchBlob: String` once on `SettingDefinition.init`; debounce **all** non-empty search queries by `100ms` (including the first character) in `SettingsView.swift:271-278`.
  4. **Pre-parse `FontFeatureEditor` map once per render**: Parse `entries` once into `[String: Bool]` (`var states: [String: Bool]`) at the top of `FontFeatureEditor.body` ($O(E)$ instead of $O(F \times E)$).

---

#### [UI-PERF-03] `P0` — Full ~540-Line Ghostty Theme Rebuild, Synchronous Main-Thread Disk Write & Double Font-Size Re-Application on Every Setting Apply
- **Locations**:
  - `Foundation/RayonTerminal/Sources/RayonTerminal/RayonTerminalConfiguration.swift:104-143`
  - `Foundation/RayonTerminal/Sources/RayonTerminal/Settings/TerminalSettings.swift:228-260`
  - `Foundation/RayonTerminal/Sources/RayonTerminal/RayonTerminalView.swift:237-245`
  - `Application/Rayon/Application/SettingsEffects.swift:33-35`
  - `Application/Rayon/Interface/Terminal/TerminalPage+macOS.swift:109-111` & `TerminalView+iOS.swift:107-109`
- **Root Cause**:
  1. `RayonTerminalConfiguration.apply` (`RayonTerminalConfiguration.swift:127-143`) expands all 256 palette entries + 6 theme colors + every user setting for **both** `light` and `dark` (~540 `.custom(key, value)` value-copied array appends via `reduce` in `lines(for:dark:)`), then calls `target.setTheme(theme)` synchronously on `@MainActor` (re-parsing Ghostty config in C and refreshing all open surfaces + Settings preview).
  2. `TerminalSettings.writeNow()` (`TerminalSettings.swift:254-260`) runs `JSONEncoder` (`.prettyPrinted`, `.sortedKeys`) and `data.write(to: fileURL, options: .atomic)` (`open` + `write` + `fsync`/`rename`) synchronously on `@MainActor` on every debounced edit.
  3. `RayonTerminalConfiguration.didApply` triggers **every** `TerminalPresentation` (`RayonTerminalView.swift:237-245`) to unconditionally call `view.performBindingAction("set_font_size:\(size)")` even when `font-size` did not change. Simultaneously, `onFontSizeChange` (`SettingsEffects.swift:33-35`) writes `AppSettings.terminalFontSize`, which fires `.onChange(of: fontSize)` in `TerminalPage` / `TerminalView` -> `DispatchQueue.main.async` -> **a second redundant `performBindingAction("set_font_size:...")`** across every terminal surface!
- **Complexity (`Current` vs `Optimal`)**:
  - **Current**: $O(540)$ config line allocations + synchronous main-thread atomic file I/O + $2 \times T$ Ghostty `set_font_size` surface actions ($T$ = open terminals) on *every* setting apply.
  - **Optimal**: Cached base theme lines + background serial I/O write + $0$ `set_font_size` actions unless `effectiveFontSize` actually changed (and at most $1 \times T$ when it did).
- **Exact Fix (100% Feature Parity)**:
  1. Cache parsed/expanded `TerminalConfiguration` per `(lightThemeName, darkThemeName)` in `ThemeCatalog` / `RayonTerminalConfiguration`, overlaying only user-modified `config` keys on apply.
  2. Move `TerminalSettings.writeNow()` file serialization + `.atomic` write onto a serial background `DispatchQueue(label: ..., qos: .utility)` (keeping synchronous `queue.sync` only inside `flush()` on app termination/background).
  3. Track `lastAppliedFontSize: Double?` in `TerminalPresentation` (`RayonTerminalView.swift:237-245`) so `performBindingAction("set_font_size:...")` only fires when `size != lastAppliedFontSize`, and remove the duplicate `TerminalPage`/`TerminalView` `.onChange(of: fontSize)` -> `setTerminalFontSize` loop (since `didApply` already updates every mounted `TerminalPresentation`).

---

#### [UI-PERF-04] `P1` — Synchronous Disk/Plist/Markdown/CoreText Reads & Unused `@ObservedObject` Inside Settings `body`
- **Locations**:
  - `Application/Rayon/Interface/Settings/AboutSettings.swift:31-37`
  - `Application/Rayon/Interface/Settings/LicenseSheet+macOS.swift:28-33`
  - `Application/Rayon/Interface/Settings/DiagnosticsSettings.swift:73-75, 155-177`
  - `Application/Rayon/Interface/Settings/DataSettings+macOS.swift:25`
  - `Foundation/RayonTerminal/Sources/RayonTerminal/Settings/Catalog/SettingValues.swift:133-135`
  - `Foundation/RayonTerminal/Sources/RayonTerminal/Settings/Views/FontEditors.swift:65-68`
  - `Foundation/RayonTerminal/Sources/RayonTerminal/Settings/Catalog/FontLibrary.swift:89-154`
  - `Foundation/RayonTerminal/Sources/RayonTerminal/Settings/Views/ConfigNavigation.swift:6-36`
- **Root Cause**:
  1. `AboutSettings.commit` (`AboutSettings.swift:31-37`) reads `BuildInfo.plist` from disk via `NSDictionary(contentsOf: url)` on every `body` evaluation.
  2. `AboutDocument.text` (`LicenseSheet+macOS.swift:28-33`) synchronously loads `LICENSE` / `EULA` from disk inside `body`, and `PrivacyPolicySheet` (`DiagnosticsSettings.swift:155-177`) synchronously reads and parses full Markdown (`AttributedString(markdown:)`) during `@State` initialization on the main thread.
  3. `TelemetryReportsSheet.json` (`DiagnosticsSettings.swift:73-75`) is a computed property that re-runs `TelemetryCenter.shared.encodedReportsJSON()` twice per `body` (`Text(json)` + `ShareLink(item: json)`).
  4. `DataSettings+macOS.swift:25` declares `@ObservedObject private var store = RayonStore.shared` without reading `store` anywhere in `body`, causing every `RayonStore` change (e.g. background SSH banner update) to invalidate `GeneralSettings`!
  5. `Double.configText` (`SettingValues.swift:133-135`) constructs `Locale(identifier: "en_US_POSIX")` + `FloatingPointFormatStyle` on every slider tick.
  6. `FontFamilyList` (`FontEditors.swift:65-68`) renders every family row in `.custom(family.name, size: 14)`, instantiating hundreds of CoreText font faces during popover open/scroll; `FontLibrary.axes`/`features` (`FontLibrary.swift:89-154`) run synchronous `CTFontCopyVariationAxes`/`CTFontCopyFeatures` on `@MainActor`.
  7. `ConfigNavigation` (`ConfigNavigation.swift:7-9`) marks `selection`, `history`, and `index` as three separate `@Published` properties, firing **3 `objectWillChange` notifications** per `go(_:)` and **2** per `step(_:)`.
- **Exact Fix (100% Feature Parity)**:
  - Cache `AboutSettings.commit` as `private static let commit: String?`; load `AboutDocument` & `PrivacyPolicySheet` Markdown via `.task` (matching `LicenseView+iOS.swift`); store `TelemetryReportsSheet` JSON in `@State`; delete unused `@ObservedObject private var store` in `DataSettings+macOS.swift:25`; hoist `private static let posixNumberFormat = FloatingPointFormatStyle<Double>(locale: Locale(identifier: "en_US_POSIX")).precision(.fractionLength(0 ... 2))` in `SettingValues.swift`; render `FontFamilyList` rows in system font (previewing the selected font in the header/preview) or lazy cell `.task`; convert `ConfigNavigation` to `@Observable` (or collapse `{ selection, history, index }` into a single `struct State`).

---

### 1B.2 Focus Area 2 — Why Animations Twitch & UI Looks Weird ("动画抽搐，UI很诡异" + Apple HIG Audit)

#### [UI-PERF-05] `P0` — Unscoped Container `.animation(..., value:)` Modifiers & Overlapping Springs Causing Layout/Scroll/Chart Twitching
- **Locations**:
  - `Application/Rayon/Interface/FileTransfer/FileTransferView+iOS.swift:56-59`
  - `Application/Rayon/Interface/Home/DashboardView+macOS.swift:22, 52, 128, 141`
  - `Application/Rayon/Interface/Snippets/SnippetsView.swift:60`
  - `Application/Rayon/Interface/Home/HomeView+macOS.swift:123, 166-167, 226` & `HomeView+iOS.swift:174`
  - `Application/Rayon/Interface/Monitor/MonitorPage+macOS.swift:44` & `MonitorView+iOS.swift:37`
  - `Application/Rayon/Interface/Editor/EditorPage+macOS.swift:76, 146-147, 304, 340-341`
  - `Application/Rayon/Interface/Shell/SidebarView+macOS.swift:80`
  - `Foundation/MachineStatusView/Sources/MachineStatusView/MonitorDashboard.swift:38-56`
  - `Foundation/RayonDesign/Sources/RayonDesign/Charts.swift:59, 91, 194-212, 250`, `Metric.swift:31`, `Motion.swift:22-56`, `Page.swift:71`, `Status.swift:134`
  - `Foundation/RayonTerminal/Sources/RayonTerminal/Settings/Views/TerminalPreview.swift:30, 52-66`
- **Root Cause & Apple HIG Violations (`motion.md`, `charts`)**:
  1. **4× Unscoped `.interactiveSpring()` on Root SFTP Container (`FileTransferView+iOS.swift:56-59`)**: Attaches `.animation(.interactiveSpring(), value: context.currentFileList / currentHint / currentProcessingFile / processConnection)` to the root `VStack`. During SFTP listing/transfer/delete, `currentProcessingFile` and `currentHint` update rapidly, animating `List` row heights, `TransferCard` text bounds, and overlay swaps with colliding springs.
  2. **Sparkline Wave Vertical Twitch (`Charts.swift:194-212` + `MonitorSession.swift:30-35`)**: `MonitorHistory.push` calls `samples.removeFirst()` once count exceeds 60, and `Sparkline` plots `Array(values.enumerated())` by array `offset` (`0..<60`) with `.animation(.easeOut(duration: 0.3), value: values)` AND dynamic `chartYScale(domain: 0 ... top)`. On every sample after #60, **every x-index `0..<59` changes its y-value simultaneously**, so Swift Charts vertically morphs all 60 points in place instead of advancing along time—producing a bizarre vertical "breathing/twitching" waveform—compounded by **3 stacked animation layers** (`MonitorPage:44` `.animation` + `MonitorDashboard:38-56` `.rxRise` + `Charts`/`Metric` `.animation`).
  3. **Lazy Grid Re-Entrance Flicker (`DashboardView+macOS.swift:22, 52`, `Motion.swift:22-37`)**: Applies `.rxRise(index)` (`@State shown = false`, `opacity: 0, offset(y: 8)` with up to `200ms` delay) to cells inside a `LazyVGrid`. Scrolling offscreen destroys cell `@State`; scrolling back recreates cells invisible and replays staggered entrance animations during scroll! Meanwhile `EmptyStateView` (`Page.swift:71`) applies `.rxPop()` (`scaleEffect(0.7)` bouncy spring `dampingFraction: 0.65`) on every empty folder/tab switch, violating Apple HIG Motion (*"Keep feedback animations subtle and quick; avoid gratuitous motion on navigation/state switches"*).
  4. **Quick Connect Per-Keystroke Hero Reflow (`HomeView+macOS.swift:166-167, 226`, `HomeView+iOS.swift:174`)**: `.animation(.easeOut(duration: 0.2), value: parsed)` on the centered hero `VStack` inside `GeometryReader` animates pill token widths and vertical hero centering on **every character typed** into `ssh user@host`.
  5. **Settings Live Metal Terminal Preview Height Jump & 60fps PTY Resize (`SettingsView.swift:102`, `TerminalPreview.swift:30, 52-66`)**: Switching between `General`/`Connection`/`Keyboard` (`previews == false`) and `Text`/`Colors`/`Cursor` (`previews == true`) inserts/removes a ~200pt preview bar above the `Form`, jumping the viewport; worse, `DisclosureGroup(isExpanded: $isExpanded.animation())` animates the live Metal `AppTerminalView` frame height pixel-by-pixel, triggering Ghostty Metal drawable + PTY `SIGWINCH` resize storms on every animation frame!
- **Exact Fix (100% Feature Parity)**:
  1. Remove unscoped container `.animation(..., value:)` modifiers from `FileTransferView+iOS.swift:56-59`, `HomeView+macOS.swift:226`, `HomeView+iOS.swift:174`, `DashboardView+macOS.swift:22`, `SnippetsView.swift:60`, `MonitorPage+macOS.swift:44`, and `MonitorView+iOS.swift:37`; scope transitions strictly to explicit overlay/banner insertion (`withAnimation(.snappy(duration: 0.18))` only on discrete state transitions, never on streaming progress/keystrokes).
  2. Give each `MonitorHistory` sample a monotonic `sampleID: Int` (or `timestamp: Date`) so `Sparkline` plots `(x: sample.id, y: sample.value)` and drops `.animation(.easeOut(duration: 0.3), value: values)` on 60-point arrays (or uses stable identity without vertical morphing).
  3. Delete `.rxRise` from lazy scrolling cells (`DashboardView`, `MonitorDashboard`) and delete `.rxPop()` bounce from `EmptyStateView` (`Page.swift:71`) so pages appear crisp and instantaneously like native Apple apps.
  4. Remove `.animation()` from `TerminalPreview` `DisclosureGroup` (`TerminalPreview.swift:30`) or clip a fixed-size `AppTerminalView` container during disclosure so the Metal/PTY surface never resizes mid-animation.

---

#### [UI-PERF-06] `P1` — Hand-Rolled Sidebar, Hardcoded Point Fonts (Zero Dynamic Type), `AnyView` Toolbar Hoisting & Chrome Jumps Fighting Apple HIG
- **Locations**:
  - `Application/Rayon/Interface/Shell/SidebarView+macOS.swift:52-231`
  - `Application/Rayon/Interface/Shell/PageScaffold+macOS.swift:108-281`
  - `Application/Rayon/Interface/Terminal/TerminalPage+macOS.swift:55-62, 876, 948` & `TerminalTabs+iOS.swift:210-224`
  - `Application/Rayon/Interface/Settings/SettingsWindow+macOS.swift:18-28` & `SettingsView.swift:70-149`
  - `Application/Rayon/Interface/Common/EditorForm.swift:63-73`
  - `Foundation/RayonDesign/Sources/RayonDesign/Tokens.swift:175-202` & `Controls.swift:44-112`
- **Root Cause & Apple HIG Violations (`sidebars.md`, `layout.md`, `toolbars.md`, `settings.md`, `windows.md`)**:
  1. **Fake `ScrollView` + `Button` Sidebar on macOS (`SidebarView+macOS.swift:52-231`)**: Replaces native `List(selection:)` `.listStyle(.sidebar)` with custom `ScrollView` + `VStack` + `Button`s using manual `Color.primary.opacity(0.155)` highlight and un-observed `UserDefaults.standard.integer(forKey: "NSTableViewDefaultSizeMode")`. Breaks macOS HIG sidebar vibrancy/Liquid Glass selection, Up/Down arrow keyboard navigation, VoiceOver outline semantics, and live Finder/System Settings sidebar size updates.
  2. **100% Fixed Point Sizes — Zero Dynamic Type (`Tokens.swift:175-202`, `Controls.swift:58`)**: Every typography token (`rxBody = .system(size: 13)`, `rxCaption = .system(size: 11)`, `rxCode = .system(size: 12)`) and control height (`RX.controlHeight = 28`, `tableRowHeight = 40`) is hardcoded in points instead of semantic `Font.body` / `.subheadline` / `.footnote` / `.caption` / `@ScaledMetric`, violating HIG Layout & Typography on iOS/iPadOS and clipping localized/accessible labels (`Controls.swift:60` `.fixedSize(horizontal: true, vertical: false)` + `.scaleEffect(0.97)` press twitch).
  3. **12-Slot `[AnyView]` PreferenceKey Toolbar Bridge (`PageScaffold+macOS.swift:108-281`)**: Wraps every macOS page toolbar control in type-erased `AnyView`, sends `[AnyView]` up via `PageToolbarKey`, and populates 12 fixed `ToolbarItem` slots with `.hidden(index >= controls.count)`. Destroys SwiftUI diffing identity on every page update (forcing 2-pass preference updates) and leaves hidden placeholder items in `NSToolbar`.
  4. **Window Toolbar & Terminal Tab Chrome Jumps (`TerminalPage+macOS.swift:55, 876`, `TerminalTabs+iOS.swift:210-224`)**:
     - Opening `TerminalSnippetDrawer` (`TerminalPage+macOS.swift:876`) attaches `.searchable(..., placement: .toolbar)` dynamically, injecting a search bar into the main window toolbar and shifting window toolbar items! Filter snippets with an inline search field inside the drawer instead.
     - iOS `TerminalTab` (`TerminalTabs+iOS.swift:210-224`) conditionally mounts/unmounts the close `Button` and changes `.padding(.trailing, selected ? 6 : 12)`, causing tab widths to jump when tapping between tabs.
  5. **macOS Settings Window Scene & Sheet Double-Headers (`SettingsWindow+macOS.swift:19`, `EditorForm.swift:63-73`)**:
     - `SettingsWindow` uses a resizable `Window` without disabling zoom/maximize per macOS Settings HIG (`settings.md:36`), and `SettingsView.swift:142-146` mutates `.simultaneousGesture` `GestureMask` on every sidebar selection change.
     - `EditorForm.swift:63-73` renders a manual `Text(title).padding(.top, 16)` header above a `Form(.grouped)` on macOS, creating non-standard double top padding.
- **Exact Fix (100% Feature Parity)**:
  1. Rebuild `SidebarView+macOS.swift` on native `List(selection:)` with `.listStyle(.sidebar)`, `Section`s (`Workspace`, `Active Sessions`, `Manage`), and `.contextMenu` / swipe/hover actions—gaining native macOS sidebar vibrancy, arrow-key navigation, sidebar icon size tracking, and VoiceOver automatically.
  2. Map `Tokens.swift` fonts on iOS (and scalable contexts) to semantic Dynamic Type styles (`.title2`, `.headline`, `.body`, `.callout`, `.footnote`, `.caption`, `.system(.footnote, design: .monospaced)`) and replace custom `RXButtonStyle` scale-press jitter with native `.bordered` / `.borderedProminent` / `.borderless` styles.
  3. Replace `PageToolbarKey` 12-slot `[AnyView]` hoisting (`PageScaffold+macOS.swift`) with native `.toolbar { ... }` modifiers directly on each active detail view (now cleanly supported since `MainView+macOS` renders only the active route or gates inactive terminal/desktop tabs with `.toolbar(isActive ? .visible : .hidden)`).
  4. Move `TerminalSnippetDrawer`'s search field inside the drawer (`placement: .sidebar` or inline `TextField`), keep iOS `TerminalTab` close-button slot width constant across selection states, disable window zoom on macOS Settings (`windowResizability` / `NSWindow.standardWindowButton(.zoomButton)?.isEnabled = false`), and use standard macOS sheet title/toolbar layout in `EditorForm`.

---

### 1B.3 Focus Area 3 — Theoretical-Optimal Performance Across the Entire App

#### [UI-PERF-07] `P0` — Startup & `RayonStore` Reload $O(N)$ Sequential Keychain IPCs + $N+1$ SQLite Queries + Global `objectWillChange` Broadcast
- **Locations**:
  - `Foundation/RayonModule/Sources/RayonModule/Storage/Storage.swift:173-182, 237-246, 401-422`
  - `Foundation/RayonModule/Sources/RayonModule/Storage/SecretStore.swift:39-51`
  - `Foundation/RayonModule/Sources/RayonModule/Store/RayonStore.swift:22-48, 75-125`
  - `Foundation/RayonModule/Sources/RayonModule/Store/RayonStore+Server.swift:13-30, 82-119`
  - `Foundation/RayonModule/Sources/RayonModule/Sync/CloudSync.swift:455-469`
- **Root Cause**:
  1. **$O(N + M)$ Keychain IPCs + $N+1$ SQLite queries on `@MainActor` at launch & `reload()`**: `RayonApp.init()` touches `RayonStore.shared`, calling `reload()` synchronously on `@MainActor`. `storage.records(RDMachine.self)` and `storage.records(RDIdentity.self)` call `withSecrets(_:)` (`Storage.swift:401-422`) per row: **first** invoking `SecItemCopyMatching` IPC to `securityd` for *every single machine and identity* ($250$ sequential IPC round-trips = **100–350 ms launch stall**), and on every `errSecItemNotFound` (~99% of `RDMachine` rows that have no Cloudflare secret!) executing a separate `db.getObject(fromTable: SecretPresence)` SQLite query ($N+1$ query!).
  2. **Keychain IPC + Full Index/Snapshot Rebuild + App-Wide Invalidation on Every Single-Record Update**: Calling `store.updateMachine(id) { $0.lastBanner = ... }` (on every SSH/Monitor connect, benchmarked in `Bench+macOS.swift:233`) reads SQLite + Keychain IPC on `@MainActor`, writes SQLite on `@MainActor`, and mutates `@Published public internal(set) var machines`, whose `didSet` (`RayonStore.swift:23-28`) rebuilds `machinePositions` ($O(N)$), `identityUsage` ($O(N)$), AND `WorkerSnapshot` ($O(N+M)$ dictionary copy under lock) and fires `RayonStore.objectWillChange` to **every view observing `RayonStore`**!
  3. **CloudSync Unbatched Per-Record Merges (`CloudSync.swift:455-469`)**: `fetchedRecordZoneChanges` merges remote records one by one outside a single SQLite transaction, followed by `didMergeRemoteChanges` -> full main-thread `RayonStore.reload()`.
- **Complexity (`Current` vs `Optimal`)**:
  - **Current**: Launch/reload = $O(N + M)$ `securityd` IPC calls + $O(N + M)$ SQLite queries on `@MainActor`; single-machine `lastBanner` update = $1$ Keychain IPC + $O(N + M)$ index/snapshot rebuilds + $O(V_{\text{app}})$ global view invalidations.
  - **Optimal**: Launch/reload = **$1$ batch `SecItemCopyMatching` IPC (`kSecMatchLimitAll`) + $1$ SQLite query per table** (~1–2 ms total!); single-machine non-secret update = **$0$ Keychain IPCs + $O(1)$ incremental index/snapshot update + $O(1)$ targeted observation**.
- **Exact Fix (100% Feature Parity)**:
  1. Add `SecretStore.allData() -> (Result<[String: Data], Error>)` using a single `SecItemCopyMatching` query with `kSecMatchLimit: kSecMatchLimitAll`, `kSecReturnAttributes: true`, `kSecReturnData: true` for `kSecAttrService == service`, plus a single `SELECT key FROM SecretPresence` query in `Storage.records(_:)`. Join secrets in memory in $O(1)$ hash lookup per row!
  2. In `Storage.update(_:id:_:)` (`Storage.swift:237-255`), pass existing in-memory secrets or only read/write Keychain when `updated.secrets != current.secrets`.
  3. Update `machinePositions`, `identityUsage`, and `WorkerSnapshot` incrementally in $O(1)$ inside `applySavedMachine` / `updateMachine`, and batch `CloudSync` `fetchedRecordZoneChanges` inside a single `db.run(transaction:)`.

---

#### [UI-PERF-08] `P0` — $O(N)$ Per-Row Singleton `@ObservedObject` Fan-Out & Uncached $O(N \log N)$ Group Sorting in `ServersView`, `DashboardView` & `SidebarView`
- **Locations**:
  - `Application/Rayon/Interface/Servers/ServersView+macOS.swift:75, 207-237, 308-338`
  - `Application/Rayon/Interface/Servers/ServersView+iOS.swift:49, 63`
  - `Application/Rayon/Interface/Servers/ServerActions+macOS.swift:65-86`
  - `Application/Rayon/Interface/Home/DashboardView+macOS.swift:70-83` & `DashboardView+iOS.swift:69-74`
  - `Application/Rayon/Interface/Shell/SidebarView+macOS.swift:18-22, 239-243` & `ContentView+iOS.swift:48-52, 117-121, 199-203`
- **Root Cause**:
  1. Every row in `ServersTable` (up to 4 columns per row!) and every `ServerTile` in `DashboardView` mounts `ServerLiveReader` (`@ObservedObject var monitors = MonitorCenter.shared`, `@ObservedObject var terminals = TerminalManager.shared`) and `UUReachable` (`@ObservedObject var account = UURemoteAccount.shared`). Opening/closing **any** terminal tab or monitor session fires `objectWillChange` into **$O(N)$ rows simultaneously** (600+ subview invalidations for 200 servers!).
  2. `ServersView+macOS.swift:75` computes `store.serverGroups(matching: searchText, sortedBy: sortOrder)` ($O(N \log N)$ localized string comparisons) inside `body` on every `RayonStore` tick, and `ServersView+iOS.swift:49, 63` calls `groups` **twice per `body` evaluation**!
- **Complexity (`Current` vs `Optimal`)**:
  - **Current**: $O(N)$ row invalidations per terminal/monitor event + $O(N \log N)$ re-sorting per `body`.
  - **Optimal**: $O(1)$ — compute `connectedMachineIDs: Set<UUID>` and `monitorSessionsByMachine: [UUID: MonitorSession]` **once** at the table/grid parent, pass value props (`isConnected: Bool`, `monitorSession: MonitorSession?`) to rows so only the 1 affected row observes its own `MonitorSession` (and only `machine.isUURemoteDevice` rows observe `UURemoteAccount`), and compute `let groups = self.groups` once or cache by `(machinesRevision, foldersRevision, searchText, sortOrder)`.

---

#### [UI-PERF-09] `P1` — `CodeEditor` Runs $O(N)$ Full-Document String Equality & 2,000-Line Indentation Scan on Every Single Keystroke
- **Locations**:
  - `Foundation/RayonModule/Sources/RayonModule/FileTransfer/EditorWorkspace.swift:42-46`
  - `Foundation/RayonEditor/Sources/RayonEditor/CodeEditor+AppKit.swift:64-95, 114-117, 250-258`
  - `Foundation/RayonEditor/Sources/RayonEditor/CodeEditor+UIKit.swift:90-95, 144-147`
- **Root Cause**:
  On **every keystroke** in a remote/local file (up to 4 MB in `EditorWorkspace.maxDocumentBytes`):
  1. `EditorDocument.text.didSet` (`EditorWorkspace.swift:44`) executes `let edited = text != savedText` — an **$O(N)$ up-to-4MB byte-by-byte string comparison** on the main thread!
  2. `CodeEditor.body` (`CodeEditor+AppKit.swift:65`) calls `Self.configuration(for: text, ...)`, running `EditorIndentation.detect(in: text)` (**scanning up to 2,000 lines on every character typed!**).
  3. `.onChange(of: text)` (`CodeEditor+AppKit.swift:74`, `CodeEditor+UIKit.swift:144`) calls `textSync.show($0)` / `textView.text != text`, bridging `NSTextStorage` / Runestone's buffer into a brand-new heap `String` ($O(N)$ copy) and comparing `controller.text != text` ($O(N)$) just to discover the edit came from the editor itself!
- **Complexity (`Current` vs `Optimal`)**:
  - **Current**: $O(N)$ string allocation + $2 \times O(N)$ full-file comparisons + $O(2000\text{ lines})$ scan **per keystroke**.
  - **Optimal**: **$O(1)$ per keystroke** — detect `EditorIndentation` once when `EditorDocument` opens/reloads; guard `textSync.show` / `updateUIView` with an `isUpdatingFromTextView: Bool` / revision counter so user keystrokes never copy `controller.text` or diff against `savedText` synchronously (mark `isEdited = true` immediately on delegate edit, or debounce clean-check).

---

#### [UI-PERF-10] `P1` — Terminal & PTY Data Path Redundant UTF-8 String Round-Trips & Per-Read 64 KB Heap Allocations
- **Locations**:
  - `Foundation/RayonModule/Sources/RayonModule/Terminal/TerminalContext.swift:275-284`
  - `Foundation/RayonModule/Sources/RayonModule/Terminal/TerminalContext+Local.swift:54-56`
  - `Foundation/RayonModule/Sources/RayonModule/Terminal/PseudoTerminalIO.swift:48-55`
  - `Foundation/RayonTerminal/Sources/RayonTerminal/RayonTerminalView.swift:21-24`
  - `Foundation/RayonModule/Sources/RayonModule/Snippet/BatchSnippetExecContext.swift:57-68, 183, 206-219`
- **Root Cause**:
  1. **SSH & Local PTY UTF-8 Round-Trip (`ByteBuffer -> [UInt8] -> String -> Data -> Ghostty`)**: `TerminalContext.swift:275-284` copies `ByteBuffer` into `[UInt8]`, decodes UTF-8 into `String`, hops to `@MainActor`, calls `surface.write(String)`, and `RayonTerminalView.swift:22` **immediately re-encodes `Data(string.utf8)`** to feed Ghostty (`session.backend.receive(Data)`). Aside from 3 heap allocations per chunk, splitting multi-byte UTF-8 sequences across SSH packet boundaries inserts U+FFFD replacement characters (`String(decoding: bytes, as: UTF8.self)`), whereas Ghostty's own VT parser natively handles streaming UTF-8 bytes!
  2. **Per-Event 64 KB Buffer Allocation (`PseudoTerminalIO.swift:50`)**: `var buffer = [UInt8](repeating: 0, count: 65536)` allocates and zeroes 64 KB on the heap on **every single `DispatchSourceRead` wakeup** instead of reusing one buffer on the serial `pty` queue.
  3. **5-Copy Snippet Output Trimming (`BatchSnippetExecContext.swift:57-68, 206-219`)**: Converts `ByteBuffer -> [UInt8] -> String -> Data(output.utf8) -> Data(dropFirst) -> String -> Data` on every output chunk.
- **Complexity (`Current` vs `Optimal`)**:
  - **Current**: 3–5 heap copies + UTF-8 validation/re-encoding per PTY/SSH packet + 64 KB allocation per read wakeup.
  - **Optimal**: **1 copy from NIO/read syscall into `Data` (or `ByteBufferView`) straight into `session.backend.receive(Data)`**, preserving split multi-byte UTF-8 sequences cleanly and reusing a single 64 KB buffer on `PseudoTerminalIO`'s serial queue.

---

#### [UI-PERF-11] `P1` — SFTP Transfer Progress Spawns Up to 6,250 `@MainActor` Tasks & 18,750 `@Published` Mutations/Sec on Fast Links
- **Locations**:
  - `Foundation/RayonSSH/Sources/RayonSSH/SFTPSession.swift:170, 281, 342-360`
  - `Foundation/RayonModule/Sources/RayonModule/FileTransfer/FileTransferContext.swift:67-69, 262-270`
- **Root Cause**:
  `SFTPSession` calls `meter.advance(by: chunk.readableBytes)` on **every 32 KB SFTP chunk** (`SFTPSession.swift:170, 281`). At 200 MB/s (local VM / 10GbE LAN), `FileTransferContext.reportProgress` spawns **6,250 unstructured `Task { @MainActor in ... }` per second**, each allocating a new `Foundation.Progress` object and mutating **3 separate `@Published` properties** (`currentProcessingFile`, `currentProgress`, `currentSpeed` = **18,750 `objectWillChange` events/sec** on `@MainActor`), starving UI responsiveness (and triggering the 4× `.interactiveSpring()` animations in `FileTransferView+iOS.swift`!). Additionally, `FileTransferContext.currentUrl` (`FileTransferContext.swift:67-69`) allocates `URL(fileURLWithPath: currentDir)` on every property read.
- **Complexity (`Current` vs `Optimal`)**:
  - **Current**: $O(\text{bytes} / 32\text{ KB})$ `@MainActor` tasks and $3\times$ `@Published` invalidations/sec.
  - **Optimal**: **$O(1)$ bounded 15–20 Hz (`50ms` `ContinuousClock` throttle in `TransferMeter.advance`, always emitting first & final chunk)** publishing a single `TransferProgressSnapshot` struct (`1` `@Published` write at $\le 20\text{ Hz}$).

---

#### [UI-PERF-12] `P2` — Per-Log-Line `open`/`stat`/`close` Syscalls, Uncached SSH Pool HMAC Hex Formatting & Remote Desktop Cursor `UIImage` Re-Wrapping
- **Locations**:
  - `Foundation/Logger/Sources/Logger/LogStore.swift:35-51, 87-91`
  - `Foundation/RayonModule/Sources/RayonModule/SSH/SSHConnectionPool.swift:87-126`
  - `Foundation/RayonModule/Sources/RayonModule/RemoteDesktop/UI/RemoteDesktopCanvas.swift:21, 222-236, 787`
- **Root Cause & Optimal Fix**:
  1. **`LogStore.append` (`LogStore.swift:35-51`)**: Constructs ISO8601 `FormatStyle` on the caller thread and runs `fileExists` + `FileHandle(forWritingTo:)` (`open`) + `seekToEnd` + `write` + `close` + `attributesOfItem` (`stat`) on **every log message**. **Fix**: Keep one open `FileHandle` + tracked `currentSize: Int` on `LogStore.queue` (1 `write` syscall per log line) and format timestamps on `queue` using a reusable `ISO8601DateFormatter` / integer formatter.
  2. **`SSHConnectionPool.secretsFingerprint` (`SSHConnectionPool.swift:116-126`)**: Runs `map { String(format: "%02x", $0) }.joined()` (64 `NSString` `snprintf` calls) + `Data(value.utf8)` copies across all auto-auth identities on every `lease()`. **Fix**: Hash UTF-8 spans directly via `value.withUTF8 { hash.update(bufferPointer: UnsafeRawBufferPointer($0)) }` and compare raw `HMAC<SHA256>.MAC` bytes (or hex-encode via lookup table) without `String(format:)`.
  3. **`RemoteDesktopCanvas` (`RemoteDesktopCanvas.swift:21, 225, 787`)**: While `RemoteDesktopFrameView` (`AVSampleBufferDisplayLayer` + `IOSurface`) is already optimal zero-copy GPU rendering, `applyCursor` (`RemoteDesktopCanvas.swift:225`) wraps `UIImage(cgImage: image)` on every cursor move even when `cursor.image === lastCursorCGImage`; cache `lastCursorCGImage` so pointer movement only updates `cursorPosition` + `cursorView.frame`.

<!-- END SECTION: AUDIT-UI-PERF -->

---

<!-- SECTION: AUDIT-WHEELS -->
## 1C. Hand-Rolled Wheels vs Mature Libraries Audit

- Status: `COMPLETED` (Audited all 9 Swift packages under `Foundation/*`, all 92 Swift files in `Application/Rayon/**`, `Workflow/Scripts/**`, and cross-referenced `../FlowDown` + `libghostty-spm` + `Citadel` checkouts)

### Post-v3.0 Baseline & License Gate

1. **What v3.0 Already De-Wheeled (Do Not Re-Litigate from Pre-v3.0 `docs/architecture-review.md`)**:
   - **Storage & Secrets**: Migrated from AES-CBC blobs to `WCDBSwift` (`Lakr233/wcdb.xcframework`), `BetterCodable`, `OrderedCollections`, and Apple Data Protection Keychain (`SecretStore.swift`).
   - **Cloud Sync & Backups**: Migrated to Apple `CKSyncEngine` + `CKRecord.encryptedValues` (`CloudSync.swift`) and `ZIPFoundation` + `CryptoKit` AES-GCM (`BackupArchive.swift`).
   - **Settings, Dialogs, Pickers & Updates**: Adopted `Lakr233/ConfigurableKit`, `Lakr233/AlertController`, `SPIndicator` (iOS), `xnth97/SymbolPicker`, `Lakr233/BlossomColorPicker`, `Lakr233/DpkgVersion`, and `os.Logger`.
   - **SSH, Terminal, Editor & UU Remote**: Adopted `Citadel` + `swift-nio-ssh` + `NIOTransportServices` (`Network.framework`), `Lakr233/libghostty-spm`, `Runestone` (iOS) + `CodeEditSourceEditor` (macOS), `Swift Charts`, and `mizorewww/UURemoteKit`.
2. **License Gate (`make scan-license` / `Workflow/Scripts/libraries.py`)**:
   - `libraries.py` strictly validates every pin in `*Package.resolved` against `Resources/LICENSE` and **only accepts permissive licenses (`MIT`, `BSD-3-Clause`, `Apache-2.0`)**. GPL/LGPL libraries (e.g. `LibVNCClient`) are incompatible; every third-party SPM replacement recommended below is verified `MIT`, `BSD-3-Clause`, or `Apache-2.0`.

---

### Complete Inventory of Remaining Hand-Rolled Wheels & Dead Leftovers

#### A. Dead Leftover Directories & Unused `RayonDesign` APIs

| ID | File Path(s) & Exact Line Count | Status | Why It Is a Wheel / Maintenance & Perf Burden | Exact Mature Replacement (Preserving 100% Features) |
| :--- | :--- | :--- | :--- | :--- |
| **W01** | `Foundation/Keychain/` (0 tracked files, leftover `.swiftpm`)<br>`Foundation/SymbolPicker/` (0 tracked files, leftover `.swiftpm`)<br>`External/NSRemoteShell/` & `External/XTerminalUI/` (leftover `.swiftpm` + `CSSH`)<br>`DerivedData/` (root pre-`.build/DerivedData` dir) | **Completely Unused** | Stale untracked directories left on disk after pre-v3.0 package removals (`Foundation/SymbolPicker` was replaced by `xnth97/SymbolPicker`; `Keychain` by `SecretStore.swift`; `External/*` by `Citadel` + `libghostty-spm`). Confuses workspace searches and tooling. *(Note: `Application/RayonUITests/` [19L README + `project.yml` + 1 test file] is git-tracked for manual iOS simulator smoke tests, though unwired in `Makefile`/CI.)* | Move untracked leftover directories (`Foundation/Keychain`, `Foundation/SymbolPicker`, `External`, root `DerivedData`) to Trash via `/usr/bin/trash`. |
| **W02** | `Foundation/RayonDesign/Sources/RayonDesign/`:<br>- `Form.swift` (128L: `RXFormRow`, `SwitchRow`)<br>- `Page.swift` (283L: `TableHeaderLabel`, `TableGroupRow`, `readWidth`/`WidthKey`)<br>- `Controls.swift` (269L: `RXValueField`, `rxFieldBackground`, `rxPlain`)<br>- `Metric.swift` (216L: `LabeledMetric`, `durationFormatter`)<br>- `Charts.swift` (265L: `rxUsageColor`, `SplitBar.Segment` unused externally)<br>- `Motion.swift` (64L: `rxArrive`, `rxPop`)<br>- `Tokens.swift` (205L: 44 unused color/font/size tokens incl. `rxTerminalForeground/Cursor/Red/Green/...`, `rxPageTitle`, `rxSheetTitle`, `rxMetricXL`) | **Partially Dead** (~450+ LOC of 1,996L total have **0 external callers**) | Leftover custom design-system primitives superseded when Settings and Tables partially migrated to native SwiftUI `Form` and `Table`. `readWidth` uses a legacy `GeometryReader` + `PreferenceKey` feedback loop. Keeping dead wrappers bloats compile times and invites new non-native usage. | Delete all zero-caller structs, modifiers, and tokens per `AGENTS.md` (*"Delete dead code instead of keeping it 'just in case'"*). Where width measurement is needed anywhere else, use SwiftUI native `.onGeometryChange(for: CGFloat.self)` (macOS 15+ / iOS 18+, back-deployed to macOS 14 / iOS 16). |

---

#### B. `RayonTerminal` Hand-Rolled Ghostty Config, Keybindings, Shortcut Recorder & Parsers (`4,100` Swift LOC + `6,249` JSON LOC)

| ID | File Path(s) & Exact Line Count | Status | Why It Is a Wheel / Bugs, Perf & Maintenance Burden | Exact Mature Replacement (Preserving 100% Features) |
| :--- | :--- | :--- | :--- | :--- |
| **W03** | `Foundation/RayonTerminal/Sources/RayonTerminal/Configuration/`:<br>- `Keybinding.swift` (108L)<br>- `KeybindingNames.swift` (201L)<br>- `KeybindingEditor.swift` (554L)<br>- `Resources/keybindings.json` (700L)<br>- `Workflow/Scripts/GhosttyConfig/export-keybinds.ts` (2L)<br>**Total: 1,565L** | **Active** | Re-implements Ghostty's `trigger=action:arg` parser, modifier alias map (`cmd`/`super`, `opt`/`alt`), camelCase-to-snake_case `NSRegularExpression` key normalizer, and action parameter validator in Swift. `Keybinding.init(entry:)` re-parses and runs regex normalization repeatedly during settings search and table rendering, and silently drifts whenever `libghostty-spm` adds actions/flags. | **`libghostty-spm` (`GhosttyKit` + `GhosttyTerminal`, MIT — already linked)**: Validate keybind and config entries via `ghostty_config_new` / `ghostty_config_finalize` / `ghostty_config_diagnostics_count` / `ghostty_config_get_diagnostic` and query triggers with `ghostty_config_trigger`; use `GhosttyTerminal.TerminalKey` for canonical key names, and parse `Keybinding` structs **once** when `TerminalSettings` mutates rather than inside view/search loops. |
| **W04** | `Foundation/RayonTerminal/Sources/RayonTerminal/Configuration/ShortcutRecorder.swift` (**260L**) | **Active** | Hand-rolled AppKit `NSViewRepresentable` installing a process-wide `NSEvent.addLocalMonitorForEvents` + a hardcoded 39-entry Carbon `keyCode` map (missing F13–F20, keypad keys, JIS/ISO international keys, and dead-key translation), plus a hand-rolled UIKit `UIViewRepresentable` `Catcher` + hardcoded `UIKeyboardHIDUsage` table on iOS. | **macOS**: **`sindresorhus/KeyboardShortcuts` (MIT)** recorder control (or native responder key capture) paired with **`GhosttyTerminal`'s `TerminalKey` (`TerminalKey+AppKit.swift` / W3C key tables in `libghostty-spm`, MIT)** so every key Ghostty itself supports is recorded accurately on both macOS and iOS. |
| **W05** | `Foundation/RayonTerminal/Sources/RayonTerminal/Configuration/`:<br>- `GhosttyConfigImport.swift` (46L)<br>- `RayonTerminalConfiguration.swift` (145L)<br>- `TerminalThemes.swift` (89L)<br>- `Resources/themes.json` (4,214L)<br>**Total: 4,494L** | **Active** | 1) `GhosttyConfigImport` and `runtimeDefaults` naively split `config.ghostty` lines on `=` (ignoring Ghostty `config-file` includes and quoting rules).<br>2) `RayonTerminalConfiguration.lines(for:dark:)` manually formats `colorKeys` + 256 palette lines instead of calling `GhosttyThemeDefinition.toTerminalConfiguration()`.<br>3) Bundles a 4,214-line `themes.json` decoded into memory on launch alongside `libghostty-spm`'s `GhosttyThemeCatalog`. | **`libghostty-spm` (`GhosttyKit` + `GhosttyTheme`, MIT — already linked)**: Load user/default Ghostty files with `ghostty_config_load_file` / `ghostty_config_load_default_files` / `ghostty_config_get`; serialize themes via `GhosttyThemeDefinition.toTerminalConfiguration()`; upstream or lazy-load supplemental themes via `GhosttyThemeCatalog` instead of decoding 4,214 lines of JSON eagerly on launch. |
| **W06** | `Foundation/RayonTerminal/Sources/RayonTerminal/Configuration/`:<br>- `SettingValues.swift` (136L: `FontFeatureValue` 34L, `DurationValue` 46L, `PairValue`, `LengthValue`)<br>- `CodepointMapping.swift` (52L)<br>**Total: 188L** | **Active** | `FontFeatureValue` is a manual byte-by-byte Swift port of Ghostty's Zig `font/shaper/feature.zig` OpenType feature parser; `DurationValue` hand-parses `1d2h3m4s5ms` strings; `CodepointMapping` hand-parses `U+XXXX-U+YYYY=Font`. | Delegate config value validation to **`ghostty_config_t` diagnostics (`libghostty-spm`)**; read OpenType feature tags directly from **Apple `CoreText`** (`CTFontCopyFeatures`) and use Swift `Regex` / `Duration` formatting for UI controls. |
| **W07** | **4x Duplicated Color Hex / CSS Parsers**:<br>- `RayonTerminal/Configuration/ColorControl.swift` (131L, lines 52–90)<br>- `RayonDesign/Tokens.swift` (`rxRGBA`, lines 186–204)<br>- `RayonEditor/EditorPalette.swift` (`Swatch`, 29L)<br>- (`GhosttyTerminal.TerminalColor` already exists in `libghostty-spm`)<br>**Total: ~200L** | **Active** | `ColorControl.swift` hardcodes only 22 CSS color names (breaking X11 color names like `rebeccapurple` or `darkslategray` that Ghostty supports!) and manually extracts `CGColorSpace.sRGB` components; hex parsing is re-implemented 3 separate times across packages. | Use **`GhosttyTerminal.TerminalColor` / `ghostty_config_get` (`ghostty_config_color_s`)** for Ghostty color values, **SwiftUI native `Color.Resolved` (`color.resolve(in: environment)`)** (macOS 14+ / iOS 17+) for sRGB component extraction, **Asset Catalog colors** for design tokens, and keep **`BlossomColorPicker` (MIT, already linked)** + native `ColorPicker` for UI. |
| **W08** | `Foundation/RayonTerminal/Sources/RayonTerminal/Configuration/`:<br>- `FontLibrary.swift` (173L)<br>- `FontEditors.swift` (373L)<br>**Total: 546L** | **Active** | Enumerates every system font descriptor via `CTFontCollectionCreateMatchingFontDescriptors`, groups families manually, and builds a custom searchable popover font picker from scratch (causing measurable first-open work on the Fonts settings page). | **Apple AppKit `NSFontPanel` / `NSFontManager` (macOS)** and **UIKit `UIFontPickerViewController` (iOS)** for native font family selection, retaining only a minimal `CoreText` `CTFontCopyVariationAxes` / `CTFontCopyFeatures` helper for the currently chosen font's `font-variation` and `font-feature` rows so 100% of Ghostty font settings remain intact. |
| **W09** | - `RayonTerminal/Configuration/SettingUndoRun.swift` (98L)<br>- `RayonTerminal/Configuration/ConfigNavigation.swift` (37L)<br>- `RayonModule/FileTransfer/FolderHistory.swift` (51L)<br>**Total: 186L** | **Active** | `SettingUndoRun` builds a custom global `NotificationCenter` + `ObjectIdentifier` undo-coalescing state machine; `ConfigNavigation` and `FolderHistory` duplicate the exact same hand-rolled back/forward cursor array in two modules. | Use **Foundation `UndoManager` (`groupsByEvent` / Slider `onEditingChanged` boundary)** instead of `NotificationCenter` observer state machines, and replace `ConfigNavigation` + `FolderHistory` with `NavigationPath` or a single shared 25-line generic `HistoryStack<Value: Equatable>`. |

---

#### C. `RayonDesign` & `Application/Rayon` Hand-Rolled UI Controls, Sidebars, Toolbars, Modals & Formatters

| ID | File Path(s) & Exact Line Count | Status | Why It Is a Wheel / Bugs, Perf & Maintenance Burden | Exact Mature Replacement (Preserving 100% Features) |
| :--- | :--- | :--- | :--- | :--- |
| **W10** | `Application/Rayon/Interface/Shell/SidebarView+macOS.swift` (**347L**) | **Active** | Hand-rolls an entire macOS source-list sidebar out of `ScrollView` + `VStack` + custom `SidebarRow` + hardcoded pixel offsets (`18.5`, `36.5`, `0.155` opacity) + reading private AppKit key `UserDefaults.standard.integer(forKey: "NSTableViewDefaultSizeMode")`. Loses native macOS sidebar material/vibrancy selection, keyboard arrow/type-ahead navigation, live sidebar-size updates, and VoiceOver outline semantics — whereas `SettingsView.swift:11938` right next door uses native `List(selection:).listStyle(.sidebar)`! | **SwiftUI native `List(selection:)` + `.listStyle(.sidebar)` + `Section` + `.badge(...)`** (matching `SettingsView.swift` and `ContentView+iOS.swift`'s iPad `SidebarView`). |
| **W11** | `Foundation/RayonDesign/Sources/RayonDesign/Page.swift:32-72` (`EmptyStateView`, **41L**) + **26 call sites** across `Application/` & `MachineStatusView/` | **Active** | Re-implements SwiftUI's native `ContentUnavailableView` with fixed-size fonts while 8 other views in the same app (`ServerPicker`, `IdentityPicker`, `LibrariesView`, etc.) already use native `ContentUnavailableView`! | **SwiftUI native `ContentUnavailableView(_:systemImage:description:)` and `ContentUnavailableView { ... } description: { ... } actions: { ... }`** (macOS 14+ / iOS 17+). |
| **W12** | `Foundation/RayonDesign/Sources/RayonDesign/Controls.swift` (`RXButtonStyle` + `RXIconButton`, **210L**) + **110 `.buttonStyle(.rx...)` call sites** | **Active** | Custom capsule `ButtonStyle` tracking `@State private var hovered` on every button instance (including inside table/list rows!), custom press scaling (`0.985`), and manual disabled opacity (`0.42`) instead of platform button styles. | **SwiftUI native `.buttonStyle(.bordered)`, `.borderedProminent`, `.borderless` (and `.glass` on OS 26)** + `.controlSize(.small / .regular)` + `Button(role: .destructive)`. Eliminates per-button `@State` hover observers across rows/tiles. |
| **W13** | `Foundation/RayonDesign/Sources/RayonDesign/Page.swift:127-205` (`SheetScaffold`, **79L**) + `Controls.swift:212-269` (`RXField`, **58L**) across **15 sheets** | **Active** | Half the app's editors (`ServerEditor`, `IdentityEditor`, `SnippetEditor`) use native `Form(.grouped)` + `.toolbar` `.cancellationAction`/`.confirmationAction`, while 15 other sheets (`PortForwardEditorSheet`, `BackupExportSheet`, `FilePromptSheet`, `UURemoteSessionPickerSheet`, etc.) use custom `SheetScaffold` + `RXField` + `RXDividedStack` pseudo-tables (`PickerSheets+macOS.swift` 318L). | **SwiftUI native `Form` (`.formStyle(.grouped)`) + `Table` / `List(selection:)` + `.toolbar { ToolbarItem(placement: .cancellationAction / .confirmationAction) }`** (matching `EditorForm.swift` and `ServerPicker.swift`). |
| **W14** | **Custom Imperative Sheet / Modal Routers**:<br>- macOS: `AppRouter+macOS.swift:12603-12662` + `MainView+macOS.swift:13149-13220` (`WindowSheet` + `WindowReader`, **132L**)<br>- iOS: `PlatformSupport/iOS/UIViewController.swift` (68L) + `UIWindow.swift` (63L) + `RayonUtil+iOS.swift` (31L) (`ModalPresenter` + `shutUpKeyWindow`, **162L**)<br>**Total: 294L** | **Active** | macOS tracks sheets by `NSWindow.windowNumber` via an AppKit `NSViewRepresentable` probe and `NSSound.beep()` on collision; iOS crawls `UIWindowScene` / `UISplitViewController` / `UITabBarController` hierarchies and retries on `RunLoop.main.perform`. | **Declarative SwiftUI `.sheet(item:)` / `.fullScreenCover(item:)` bound to per-scene `@State` / `@Environment` router enum** (as in `../FlowDown`), keeping **`AlertController` (MIT)** only for transient alerts/confirmations (`Indicator.swift`). |
| **W15** | - `PlatformSupport/macOS/TitleBarDoubleClick.swift` (49L)<br>- `Application/RayonApp+macOS.swift:776-828` (`installShortcutMonitor`, 53L)<br>- `Interface/Shell/PageScaffold+macOS.swift:13326-13504` (`ToolbarControls` + `[AnyView]` `PageToolbarKey` + `PageToolbarSlots`, 179L)<br>- `Interface/FileTransfer/FileTransferPage+macOS.swift:4160-4200` (`FolderHistoryPointer`, 41L)<br>**Total: 322L** | **Active** | `.rxClearToolbar()` stripped AppKit's titlebar hit-testing, forcing a hand-rolled `NSEvent` local monitor (`TitleBarDoubleClick`) that parses `AppleActionOnDoubleClick` from `UserDefaults` and hit-tests `window.contentView?.superview` on every mouse-down! `PageToolbarSlots` erases every toolbar item to `AnyView` in a `PreferenceKey` across 6 hardcoded slots (`slot(0)...slot(5)`). | **Native SwiftUI `.windowToolbarStyle(.unified)` + `.containerBackground(..., for: .window)` + standard `.toolbar` items** (restoring native macOS titlebar double-click zoom/minimize/fill automatically so `TitleBarDoubleClick.swift` can be deleted completely, and removing `[AnyView]` preference-key type erasure). |
| **W16** | **Multiple Duplicate Byte / Rate / Relative Date Formatters**:<br>- `RayonDesign/Metric.swift:126-215` (`RXFormat`, 90L)<br>- `MachineStatus/ProcParsers.swift:380-394` (`formatKilobytes`, 15L)<br>- `RayonModule/RemoteDesktop/UI/RemoteDesktopStageView.swift:14645-14649` (`rate`, 5L)<br>- `Interface/Terminal/UURemoteSessionList.swift:17508-17512` (`RelativeDateTimeFormatter`, 5L)<br>- `Interface/FileTransfer/RemoteFile+Display.swift:4789-4795` (`DateFormatter`, 7L)<br>**Total: 122L** | **Active** | Three separate hand-rolled `while value >= 1024` / `1_000_000` loops and repeated `RelativeDateTimeFormatter` / `DateComponentsFormatter` allocations producing hardcoded English units (`"KB"`, `"MB/s"`, `"Never"`). | **Apple `Foundation` FormatStyles**: `ByteCountFormatStyle` (`.formatted(.byteCount(style: .file / .memory))`), `.formatted(.number.precision(.fractionLength(0...1)))`, `Duration.UnitsFormatStyle`, and `Date.RelativeFormatStyle` (`.formatted(.relative(presentation: .named))`). |
| **W17** | `RayonDesign/Tokens.swift:127-166` (`Font.rx*`, **40L**) + hardcoded `.font(.system(size: ...))` across `Application/` & `MachineStatusView/` | **Active** | Hardcodes point sizes (`13`, `12`, `11`, `22`), violating `AGENTS.md` (*"Use ... Dynamic Type"*), preventing accessibility text scaling on iPhone, iPad, and macOS. | **SwiftUI Dynamic Type semantic styles**: `.body`, `.callout`, `.subheadline`, `.footnote`, `.caption`, `.caption2`, combined with `.monospaced()` / `.monospacedDigit()` / `.weight(...)`. |
| **W18** | `RayonModule/RemoteDesktop/UI/RemoteDesktopStageView.swift:14205, 14245-14262, 14896-14903` (~30L) + `DiagnosticsSettings.swift:10782-10866` (`PrivacyPolicySheet` custom Markdown block splitter, 85L) | **Active** | `RemoteDesktopStageView` hand-rolls a `DispatchQueue.main.asyncAfter` toast state machine (race-prone if identical strings flash within 4s); `PrivacyPolicySheet` hand-parses `AttributedString` `presentationIntent` runs into heading/bullet views. | Use **`SPIndicator` (MIT, already linked on iOS)** or cancellation-safe `.task(id: notice)` HUD on macOS; for Markdown rendering, either **`Textual` (`gonzalezreal/textual`, MIT — already used in `../FlowDown`!)** or structured `PresentationIntent` rendering if avoiding adding a dependency for 1 sheet. |
| **W19** | - `Application/Rayon/Extension/FilePicker+iOS.swift` (`UIDocumentPickerViewController` wrapper, **94L**)<br>- `Application/Rayon/Extension/OpenPanel+macOS.swift` (`NSOpenPanel` wrapper, **42L**)<br>**Total: 136L** | **Active** | Legacy 2022 UIKit/AppKit file picker wrappers kept alongside SwiftUI's native `.fileImporter` / `.fileExporter` (which `IdentityEditor.swift` and `DataBackupSettings` already use!). Note `FilePicker<LabelView>` struct (lines 1371–1407) has **0 callers** (only `FilePickerUIRepresentable` is called once in `FileTransferView+iOS.swift`). | Delete unused `FilePicker` wrapper immediately; migrate `FileTransferView+iOS` upload/folder selection to **SwiftUI native `.fileImporter(isPresented:allowedContentTypes:allowsMultipleSelection:)`** (macOS 14+ / iOS 17+ supports `.folder`, `.item`, `.fileDialogDefaultDirectory`, `.fileDialogBrowserOptions(.includeHiddenFiles)`). |

---

#### D. `RayonModule/RemoteDesktop` Hand-Rolled VNC (RFB) Stack, Clipboard Polling & Input Maps

| ID | File Path(s) & Exact Line Count | Status | Why It Is a Wheel / Bugs, Perf & Maintenance Burden | Exact Mature Replacement (Preserving 100% Features) |
| :--- | :--- | :--- | :--- | :--- |
| **W20** | `Foundation/RayonModule/Sources/RayonModule/RemoteDesktop/VNC/`:<br>- `VNCRFBClient.swift` (462L)<br>- `VNCDecoders.swift` (415L)<br>- `VNCFramebuffer.swift` (258L)<br>- `VNCRFBDriver.swift` (215L)<br>- `VNCMessages.swift` (201L)<br>- `VNCPixelFormat.swift` (170L)<br>- `VNCAppleAuth.swift` (129L)<br>- `VNCKeySyms.swift` (106L)<br>- `VNCConnection.swift` (91L)<br>- `VNCSSHTunnel.swift` (88L)<br>- `VNCInflateStream.swift` (77L)<br>- `VNCStream.swift` (56L)<br>- `VNCDES.swift` (54L)<br>**Total: 2,322L** (+ ~1,500L VNC protocol tests) | **Active** | Full hand-rolled RFB 3.3/3.7/3.8 client, pixel format translator, Raw/CopyRect/RRE/Hextile/ZRLE decoders, raw `compression_stream` zlib header stripper, `CommonCrypto` DES bit-reversed challenge cipher, and Apple Remote Desktop DH+MD5+AES-128-ECB auth (`BigInt` + `CommonCrypto`).<br>**Concrete gaps/bugs**: Missing Tight/JPEG encoding (huge bandwidth penalty over WAN/SSH!), Zlib/CoRRE, `ExtendedDesktopSize` (cannot resize remote screen or switch monitors), `ContinuousUpdates`, TLS/VeNCrypt, and UTF-8 `ExtendedClipboard` (`VNCMessages.swift:17480` degrades all CJK/emoji clipboard text to `'?'`!). | **`RoyalVNCKit` (`royalapplications/royalvnc`, MIT License — `make scan-license` compatible!)**: Mature, pure-Swift cross-platform (macOS + iOS) VNC SDK supporting Apple Screen Sharing (ARD DH+AES), standard VNC DES, Tight/JPEG, ZRLE, Zlib, Hextile, CoRRE, RRE, CopyRect, `ExtendedDesktopSize`, `ContinuousUpdates`, UTF-8 clipboard, and custom transport/tunnel hooks. Keep `VNCSSHTunnel.swift` (88L `direct-tcpip` channel over `RayonSSH`, or local loopback endpoint) and all `RDMachine` VNC settings (`vncPort`, `vncPassword`, `vncUsername`, `vncOverSSH`, `vncShared`). |
| **W21** | `Foundation/RayonModule/Sources/RayonModule/RemoteDesktop/VNC/VNCDiscovery.swift:16907-16940` (`Resolution` over `<dnssd.h>`, **~55L** of 181L) | **Active** | Combines `NWBrowser` with raw C `DNSServiceResolve` + `Unmanaged.passUnretained(self)` pointer juggling solely to turn `_rfb._tcp` Bonjour endpoints into `.local` hostnames. | Use **`RoyalVNCKit`'s built-in Bonjour discovery** or **Apple `Network.framework` `NWBrowser`** endpoint metadata / `NetService` without raw `<dnssd.h>` `Unmanaged` C callbacks. |
| **W22** | `Foundation/RayonModule/Sources/RayonModule/RemoteDesktop/RemoteDesktopSession.swift` (1.0s repeating `Timer` polling `Pasteboard.changeCount`, **~35L**) | **Active** | Polls `UIPasteboard.general.changeCount` / `NSPasteboard.general.changeCount` every 1 second on the main actor while connected, directly violating `AGENTS.md` (*"no polling timers standing in for events"*) and causing unnecessary main-thread wakeups. | **Event-driven clipboard sync**:<br>- **iOS**: Observe `UIPasteboard.changedNotification` + `UIApplication.didBecomeActiveNotification` (zero polling!).<br>- **macOS**: Check `NSPasteboard.general.changeCount` on `NSApplication.didBecomeActiveNotification` + `NSWindow.didBecomeKeyNotification` (when switching from another Mac app into Rayon to paste) + explicit Clipboard menu actions. |
| **W23** | - `RemoteDesktop/UI/RemoteDesktopCanvas.swift` (1,037L: custom `CGContext` 12-vertex arrow cursor renderer + key repeat timers)<br>- `RemoteDesktop/RemoteDesktopKeymap.swift` (195L)<br>- `RemoteDesktop/VNC/VNCKeySyms.swift` (106L)<br>**Total: 1,338L** (3rd copy of Carbon/HID keycode tables in repo!) | **Active** | Hand-draws a fallback pointer arrow polygon with raw `CGContext` coordinates instead of system cursor assets, and maintains two more Carbon/HID-to-KeySym lookup tables separate from `RayonTerminal`. | Use `NSCursor.arrow.image` (macOS) / SF Symbol or vector asset (iOS) for local pointer overlay, and unify keycode/keysym translation through **`RoyalVNCKit`** (for VNC) and a single shared HID/Carbon key table. |

---

#### E. `RayonSSH` & `RayonModule` Crypto, Wire Codecs, Networking, SFTP & Legacy Migrations

| ID | File Path(s) & Exact Line Count | Status | Why It Is a Wheel / Bugs, Perf & Maintenance Burden | Exact Mature Replacement (Preserving 100% Features) |
| :--- | :--- | :--- | :--- | :--- |
| **W24** | `Foundation/RayonModule/Sources/RayonModule/Identity/IdentityDraft.swift:90-176` (`generateEd25519KeyPair`, **86L**) + `RDIdentity.swift` / `Telemetry+Rayon.swift` key prefix sniffers | **Active** | Hand-serializes `openssh-key-v1\0` binary framing, checkints, block padding, and PEM armor byte-by-byte — duplicating code that **already exists in linked `Citadel`**! | **`Citadel` (MIT — already linked)**: Call `Curve25519.Signing.PrivateKey().makeSSHRepresentation(comment:)` (`Citadel/OpenSSHKey.swift:90`) and `SSHKeyDetection.detectPrivateKeyType` / `detectPublicKeyType` (`Citadel/SSHKeyTypeDetection.swift`). Deletes ~80 LOC immediately. |
| **W25** | `Foundation/RayonSSH/Sources/RayonSSH/`:<br>- `SSHPrivateKey.swift` (295L)<br>- `OpenSSHKeyCipher.swift` (81L)<br>- `SSHRSAKey.swift` (142L)<br>**Total: 518L** | **Active** | Hand-rolls ASN.1 DER tag/length byte walking (`parseSEC1ECPrivateKey`), OpenSSL legacy `DEK-Info` MD5 `EVP_BytesToKey`, `CommonCrypto` AES-CBC/CTR/GCM decryption, and custom `BigInt` RSA key reconstruction. Custom ASN.1/crypto parsers are high-risk maintenance surface. | **`Citadel` (MIT) + `swift-crypto` (`_CryptoExtras`) + `swift-asn1` (Apache-2.0 — all 3 already in `Package.resolved`!)**: Use `Citadel`'s `OpenSSH.PrivateKey` (`Ed25519`, `RSA`, `P256`/`P384`/`P521` + `bcrypt`), `_CryptoExtras._RSA.Signing.PrivateKey(pemRepresentation:)` / `P256.Signing.PrivateKey(pemRepresentation:)` for PKCS#1/PKCS#8/SEC1 PEM keys, retaining only a minimal cipher shim if encrypted `aes256-cbc` / `aes256-gcm@openssh.com` OpenSSH keys are needed beyond Citadel's `aes*-ctr`. |
| **W26** | `Foundation/RayonSSH/Sources/RayonSSH/SSHAgent.swift` (**319L**) + `SSHTransport.swift` `MultiThreadedEventLoopGroup` workaround | **Active** | Uses raw POSIX `Darwin.socket(AF_UNIX, SOCK_STREAM, 0)` + blocking `Darwin.connect`/`read`/`write` loops with `SO_RCVTIMEO`. Because it blocks the calling thread inside an `NIOSSHClientUserAuthenticationDelegate`, `SSHTransport.swift` is forced to allocate a separate `MultiThreadedEventLoopGroup` on macOS just so `SSHAgent` can stall the `EventLoop`! | **Apple `swift-nio` (`NIOPosix`, Apache-2.0 — already linked in `RayonSSH`!)**: Connect asynchronously over `ClientBootstrap(group:).connect(unixDomainSocketPath:)` with a simple length-prefixed `ByteToMessageDecoder` (`UInt32` big-endian frame length), completely eliminating blocking POSIX socket I/O and `EventLoop` stalls while keeping 100% support for system `ssh-agent`, 1Password, Secretive, and GPG/YubiKey agents. |
| **W27** | `Foundation/RayonSSH/Sources/RayonSSH/SOCKS5Handshake.swift` (**163L**) | **Active** | Re-implements RFC 1928 SOCKS5 server greeting, request parsing, IPv4/IPv6/FQDN decoding, and reply framing in a custom `ByteToMessageDecoder` (file header explicitly notes avoiding `swift-nio-extras`). | **Apple `swift-nio-extras` (`NIOSOCKS`, Apache-2.0 — `make scan-license` compatible!)**: Official SwiftNIO SOCKS5 server/client channel handlers (`SOCKSServerHandshakeHandler`). |
| **W28** | - `RayonSSH/SSHConnection+Session.swift:165-223` (`abandoning(...)`, **59L**)<br>- **3x Duplicated Streaming UTF-8 Byte Scanners**:<br>  1. `RayonTerminal/TerminalCallbacks.swift:64-96` (33L)<br>  2. `RayonModule/Terminal/TerminalContext.swift:10966-10976` (11L)<br>  3. `RayonModule/Terminal/TerminalContext+UURemote.swift:11342-11374` (33L)<br>**Total: 136L** | **Active** | 1) `abandoning(...)` manually coordinates `OSAllocatedUnfairLock` + `CheckedContinuation` + 2 unstructured `Task`s for timeout racing instead of structured concurrency.<br>2) Three separate files hand-roll UTF-8 continuation-byte bitmask scanners (`byte & 0xC0 == 0x80`) just to convert `ByteBuffer`/`Data` -> `String` -> UTF-8 bytes again for Ghostty! | 1) Replace `abandoning(...)` with structured `withThrowingTaskGroup` racing the operation task against `Task.sleep(for: timeout)`.<br>2) Pass raw UTF-8 `Data` / `UnsafeRawBufferPointer` directly through `TerminalSessionSurface.write(_ data: Data)` into **`libghostty-spm`** (Ghostty's VT parser handles split multi-byte UTF-8 sequences natively in C/Zig with zero intermediate `String` allocations!). |
| **W29** | `Foundation/RayonModule/Sources/RayonModule/FileTransfer/FileTransferContext+Editing.swift` (**124L**) + `FileTransferContext.swift:170-185` (`enqueue` unstructured task chain) | **Active** | `readText` and `writeText` create a temporary folder on local disk, download/upload via file-URL transfer helpers, read `Data(contentsOf:)`, and delete the scratch directory — doing unnecessary disk I/O and temp-file management for in-memory editor buffers. | **`Citadel` `SFTPClient.withFile` (MIT — already linked via `RayonSSH.SFTPSession`)**: Read and write `ByteBuffer` directly in memory (`file.readAll()` / `file.write(ByteBuffer)`), enforcing the 4 MB editor cap before reading without touching local disk. |
| **W30** | - `RayonModule/Store/RayonStore+Server.swift:8829-8960` (`importOpenSSHConfig`, **~132L**)<br>- `RayonModule/Utils/SSHCommandReader.swift` (**226L**)<br>**Total: 358L** | **Active** | `importOpenSSHConfig` splits lines naively (`key == "host"`), missing `Include` directives (used by OrbStack, Colima, Lima, Coder, Teleport), `Host *` defaults, and multi-token quoting; `SSHCommandReader` hand-rolls a shell word splitter (`split(_:)`) and flag parser. | Keep lightweight `SSHCommandReader` for Quick Connect UX (no external dependency needed, though simplify flag loop), and upgrade `importOpenSSHConfig` on macOS to optionally resolve `Include` globs (or `/usr/bin/ssh -G` per discovered host alias on macOS) so real-world `~/.ssh/config` files with `Include` blocks import cleanly. |
| **W31** | **Pre-v3.0 Legacy v2.x Compatibility & Migration Decoders**:<br>- `RayonModule/Storage/LegacyStoreImport.swift` (561L)<br>- `RayonModule/Storage/LegacyStoreImport+Notice.swift` (42L)<br>- `RayonModule/Backup/LegacyBackup.swift` (92L)<br>- `RayonModule/Settings/LegacySettingsImport.swift` (68L)<br>- `RayonModuleTests/LegacyStoreImportTests.swift` (~580L)<br>**Total: ~1,343L** | **Active (Legacy Migration Weight)** | Contains 3 generations of legacy Rayon 2.x `CommonCrypto` `CCCrypt` AES-CBC / AES-GCM / MD5 / `IOPlatformUUID` key-derivation decryptors and PropertyList decoders. Per `AGENTS.md`: *"Breaking changes are allowed when they remove legacy weight (old data formats, migrations, compatibility decoders)."* | **Product / Architecture Decision**: Once the v2→v3 migration window closes (or immediately if clean v3 cutover is desired), delete all ~1,343 LOC of legacy v2.x store/backup/settings decoders and `CommonCrypto` CBC key-derivation shims. *(Note: Do **not** alter `UUID+Derived.swift` [26L], as its deterministic SHA-256 IDs anchor existing CloudKit record names across devices.)* |

---

#### F. `RayonPTY` Local Shell Spawner & `MachineStatus` Remote Samplers

| ID | File Path(s) & Exact Line Count | Status | Why It Is a Wheel / Bugs, Perf & Maintenance Burden | Exact Mature Replacement (Preserving 100% Features) |
| :--- | :--- | :--- | :--- | :--- |
| **W32** | - `RayonModule/Sources/RayonPTY/rayon_pty.c` (111L) + `include/rayon_pty.h` (26L)<br>- `RayonModule/Terminal/LocalPseudoTerminal.swift` (81L)<br>- `RayonModule/Terminal/PseudoTerminalIO.swift` (120L)<br>- `RayonModule/Terminal/TerminalContext+Local.swift` (96L)<br>**Total: 434L** | **Active** | Custom C `forkpty` + `FD_CLOEXEC` descriptor sweep + custom `DispatchSourceRead`/`DispatchSourceWrite` + `OSAllocatedUnfairLock` pending write queue for macOS Local Terminal. | **`libghostty-spm` (`GhosttyKit`, MIT — already linked)** natively implements macOS PTY creation, login-shell environment setup, `TIOCSWINSZ`, and shell integration inside Ghostty surfaces (or, if keeping `RayonModule` decoupled from Ghostty's command runner, replace `PseudoTerminalIO`'s manual `Darwin.read`/`write` `EAGAIN` state machine with **Apple `DispatchIO`** / **`Swift System` `FileDescriptor`**, already in `Package.resolved`). |
| **W33** | `Foundation/MachineStatus/Sources/MachineStatus/`:<br>- `ProcParsers.swift` (395L)<br>- `DarwinParsers.swift` (207L)<br>- `ServerStatusSampler.swift` (178L)<br>**Total: 780L** | **Active (Mostly Legitimate Domain Code, Minor Wheel Overlap)** | Agentless SSH monitoring of remote Linux (`/proc/*`) and macOS (`vm_stat`, `df`, `netstat`, `ioreg`) hosts has no client-side Apple framework substitute. However:<br>1) `ProcParsers.formatKilobytes` (lines 380–394) duplicates `ByteCountFormatStyle`.<br>2) `ServerStatus.posixShellCommand` duplicates `RemoteShellCommand.posix` in `RayonModule`.<br>3) `DarwinParsers` parses human-readable localized/formatted `top -l 2` output for CPU usage. | Keep agentless SSH sampler architecture, but:<br>1) Replace `formatKilobytes` with `ByteCountFormatStyle` (**W16**).<br>2) Share `posixShellCommand` or keep single 5-line helper.<br>3) Prefer `sysctl` / deterministic flags (`LC_ALL=C`) in remote Darwin/Linux probes so non-English remote locales never break parsing. |

---

### Summary Priority Matrix for De-Wheeling Waves

1. **Zero-Risk Immediate Deletions (~1,800+ LOC removable)**:
   - Trash untracked dead folders (`Foundation/Keychain`, `Foundation/SymbolPicker`, `External/*`, root `DerivedData`) (**W01**).
   - Delete ~450 LOC of zero-caller public types/modifiers/tokens in `RayonDesign` (**W02**) and unused `FilePicker` wrapper (**W19**).
   - Delete ~80 LOC hand-rolled `openssh-key-v1` Ed25519 encoder in `IdentityDraft.swift` in favor of `Citadel`'s `makeSSHRepresentation` (**W24**).
   - (If approved) Remove ~1,343 LOC of v2.x legacy store/backup/settings decoders (**W31**).
2. **High-Impact Native SwiftUI & Foundation Replacements (Fixes UI Lag, Dynamic Type & Non-Native Chrome)**:
   - Replace `SidebarView+macOS.swift` (347L), `EmptyStateView` (26 sites), `RXButtonStyle` (110 sites), `SheetScaffold`/`RXField` (15 sheets), `TitleBarDoubleClick` + `PageToolbarSlots`, `RXFormat`, and fixed-point `Font.rx*` with native `List(.sidebar)`, `ContentUnavailableView`, `.bordered`/`.borderedProminent`, `Form(.grouped)`, unified `.toolbar`, `ByteCountFormatStyle`, and Dynamic Type (**W10–W19**).
   - Replace 1s clipboard polling `Timer` in `RemoteDesktopSession` with `UIPasteboard.changedNotification` + app/window activation events (**W22**).
3. **High-Leverage Library Consolidations (`libghostty-spm`, `RoyalVNCKit`, `NIOPosix`, `NIOSOCKS`)**:
   - **`RayonTerminal` -> `libghostty-spm` + `KeyboardShortcuts` (MIT) + System Font Pickers** (**W03–W09**, + raw `Data` UTF-8 feed **W28**).
   - **`RayonModule/VNC` (2,322L) -> `RoyalVNCKit` (MIT)** (**W20–W21, W23**): Gains Tight/JPEG compression, dynamic resize, multi-display, and UTF-8 clipboard while deleting ~2,200 LOC of custom RFB/crypto/decoder code.
   - **`RayonSSH` -> `NIOPosix` async Unix socket (`SSHAgent`), `NIOSOCKS` (`SOCKS5Handshake`), `Citadel`/`swift-crypto`/`swift-asn1` (`SSHPrivateKey`), and in-memory `Citadel` SFTP editing** (**W25–W29**).

<!-- END SECTION: AUDIT-WHEELS -->

---

<!-- SECTION: AUDIT-LOC-ABSTRACTIONS -->
## 1D. LOC Reduction, Over-Abstraction, Over-Testing & Over-Defensiveness Audit

- Status: `COMPLETED`

### 1D.0 Codebase LOC Baseline & Largest Files

Exact line counts across all **412 tracked source & test files (`64,164` LOC: `52,490` production + `11,674` test)** at HEAD `a582eea2` (excluding untracked workspace leftovers `Foundation/Keychain`, `Foundation/SymbolPicker`, `External/*`, and `DerivedData` already flagged in 1C-W01):

| Target / Package | Prod Files | Prod LOC | Test Files | Test LOC | Total LOC | Test : Prod |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: |
| `Application/Rayon` + `RayonUITests` | 106 | 18,175 | 1 | 161 | 18,336 | 0.9% |
| `Foundation/RayonModule` | 111 | 18,436 | 46 | 5,982 | 24,418 | 32.4% |
| `Foundation/RayonTerminal` | 26 | 4,938 | 5 | 1,069 | 6,007 | 21.6% |
| `Foundation/RayonSSH` | 20 | 3,379 | 10 | 1,980 | 5,359 | 58.6% |
| `Foundation/RayonDesign` | 13 | 2,021 | 0 | 0 | 2,021 | 0.0% |
| `Foundation/MachineStatus` | 12 | 1,565 | 5 | 913 | 2,478 | 58.3% |
| `Foundation/Telemetry` | 15 | 1,428 | 6 | 708 | 2,136 | 49.6% |
| `Foundation/MachineStatusView` | 4 | 1,177 | 1 | 94 | 1,271 | 8.0% |
| `Foundation/RayonEditor` | 7 | 583 | 3 | 132 | 715 | 22.6% |
| `Foundation/Logger` | 6 | 300 | 2 | 207 | 507 | 69.0% |
| `Server/Telemetry` (TS Worker) | 6 | 447 | 4 | 428 | 875 | 95.7% |
| `Workflow/Scripts` | 3 | 41 | 0 | 0 | 41 | — |
| **TOTAL** | **329** | **52,490** | **83** | **11,674** | **64,164** | **22.2%** |

**Top 20 Largest Files Across Repo:**
1. `Foundation/RayonSSH/Tests/RayonSSHTests/SSHLiveTests.swift` — `1,194` LOC
2. `Application/Rayon/Interface/Terminal/TerminalPage+macOS.swift` — `1,090` LOC
3. `Foundation/RayonModule/Sources/RayonModule/RemoteDesktop/UI/RemoteDesktopCanvas.swift` — `1,037` LOC
4. `Foundation/RayonModule/Tests/RayonModuleTests/VNCRFBTests.swift` — `989` LOC
5. `Foundation/RayonModule/Sources/RayonModule/RemoteDesktop/UI/RemoteDesktopStageView.swift` — `853` LOC
6. `Application/Rayon/Interface/Terminal/TerminalView+iOS.swift` — `663` LOC (`+ TerminalTabs+iOS.swift` `371` LOC = `1,034` LOC iOS terminal UI)
7. `Foundation/RayonModule/Sources/RayonModule/RemoteDesktop/RemoteDesktopSession.swift` — `577` LOC
8. `Foundation/RayonModule/Sources/RayonModule/Storage/LegacyStoreImport.swift` — `561` LOC
9. `Foundation/RayonTerminal/Sources/RayonTerminal/Configuration/KeybindingEditor.swift` — `554` LOC
10. `Foundation/RayonModule/Sources/RayonModule/Sync/CloudSync.swift` — `545` LOC
11. `Foundation/MachineStatusView/Sources/MachineStatusView/MonitorCards.swift` — `536` LOC
12. `Application/Rayon/Interface/Editor/EditorWorkspaceView+iOS.swift` — `518` LOC (`vs EditorPage+macOS.swift` `390` + `EditorWorkspace+macOS.swift` `96` = `486` LOC)
13. `Foundation/RayonSSH/Sources/RayonSSH/SSHConnection.swift` — `504` LOC
14. `Foundation/RayonModule/Sources/RayonModule/Store/RayonStore.swift` — `488` LOC
15. `Foundation/MachineStatusView/Sources/MachineStatusView/MonitorSession.swift` — `478` LOC
16. `Foundation/RayonTerminal/Sources/RayonTerminal/Configuration/SettingControl.swift` — `475` LOC
17. `Foundation/RayonModule/Sources/RayonModule/FileTransfer/FileTransferContext.swift` — `471` LOC
18. `Application/Rayon/Interface/Shell/AppRouter+macOS.swift` — `471` LOC (`vs ServerWorkspaceView+iOS.swift` `384` LOC)
19. `Foundation/RayonModule/Sources/RayonModule/RemoteDesktop/VNC/VNCRFBClient.swift` — `462` LOC
20. `Foundation/RayonModule/Sources/RayonModule/Storage/Storage.swift` — `447` LOC

---

### 1D-a. Code Slimming Without Feature Loss ("在不砍掉功能的情况下减少代码行数")

> **Hard Constraint Enforced**: Every item below preserves **100% of user-facing features, workflows, keyboard shortcuts, and settings** (`AGENTS.md`).

#### A1. Cross-Platform `*+macOS.swift` / `*+iOS.swift` & `#if os(...)` Duplication (`~1,495` Prod LOC Savable)

Every `+macOS.swift` / `+iOS.swift` pair in `Application/Rayon/Interface/**` (34 macOS files vs 38 iOS files) and `#if os(...)` fork in `Foundation/*` was compared side by side:

| ID | Duplicated Pair (`file:line`) | Action | Duplicated Logic / Views & How to Unify | Est. LOC Delta |
| :--- | :--- | :--- | :--- | ---: |
| **S01** | `Application/Rayon/Interface/Terminal/TerminalPage+macOS.swift:330-349, 486-1014` (`1,090` LOC) vs `TerminalView+iOS.swift:242-336, 581-661` (`663` LOC) + `TerminalTabs+iOS.swift:16-370` (`371` LOC) | `Unify` | Extract shared `TerminalChrome.swift` for 80–100% identical subviews: (1) byte-identical `SessionTabDropDelegate` (`770-789`) == `TerminalTabDropDelegate` (`145-164`); (2) identical `TerminalCanvasSnapDropDelegate` + `snapPreviewOverlay` (`330-349, 720-768` vs `242-261, 620-661`); (3) `TerminalStatusBar` + `LiveFigures` (`981-1014` vs `581-614`); (4) `disconnectedBanner` (`552-570` vs `318-336`); (5) `searchBar` + `moveSearch` (`486-550` vs `267-316`); (6) `SessionTabs`/`SessionTab` cluster pill strip (`573-718, 880-979` vs `16-260`); (7) `TerminalSnippetDrawer` vs `TerminalSnippetPanel` (`791-878` vs `266-369`). Keep only window/navigation bar chrome per platform. | **−420** |
| **S02** | `Application/Rayon/Interface/Editor/EditorPage+macOS.swift:118-389` (`390` LOC) + `EditorWorkspace+macOS.swift:1-96` vs `EditorWorkspaceView+iOS.swift:118-518` (`518` LOC) | `Unify` | Unify into shared `EditorWorkspaceContent.swift`: (1) byte-identical `EditorTabDropDelegate` (`175-195` vs `256-276`); (2) 95%-identical `EditorSurface` (`265-306` vs `342-377`) and `EditorStatusLine` (`310-343` vs `380-413`); (3) `OpenRemoteFileSheet` (`348-389` vs `417-469`); (4) `tabStrip` (`118-155` vs `118-154`); (5) duplicated unsaved-changes reload/close confirmation dialogs (`EditorWorkspace+macOS.swift:44-94` vs `EditorWorkspaceView+iOS.swift:482-516`). | **−265** |
| **S03** | `Application/Rayon/Interface/Snippets/BatchRunSheet+macOS.swift:16-190` (`190` LOC) vs `SnippetExecuteView+iOS.swift:15-223` (`223` LOC) | `Unify` | Unify into shared `BatchRunView.swift`: identical `BatchOutputView` (`164-188` vs `193-221`), `stateLabel`, `duration`, `seconds(_:)`, `output` pane, `serverList`, and Stop/Close confirmation logic; only outer sheet/navigation container differs (`#if os(macOS)` frame vs iOS `NavigationStack`). | **−135** |
| **S04** | `Application/Rayon/Interface/RemoteDesktop/RemoteDesktopsView+macOS.swift:16-291` (`291` LOC) vs `RemoteDesktopsView+iOS.swift:16-304` (`304` LOC) + `UURemoteAccountSheet+macOS.swift:1-34` vs `UURemoteAccountSheet+iOS.swift:1-41` | `Unify` | Extract shared `RemoteDesktopsListModel` / row components (`servers` filter/sort `23-33` vs `25-35`, `SessionPhaseLabel` `274-289` vs `291-302`, `NearbyHostRow`, `DesktopServerRow`) and merge the two 35-line `UURemoteAccountSheet` wrappers into a single cross-platform `UURemoteAccountSheet.swift`. | **−145** |
| **S05** | `Application/Rayon/Interface/Settings/DataSettings+macOS.swift:1-287` vs `DataBackupSettings+iOS.swift:1-445` + `ServersView+macOS.swift:89-108` (`importSSHConfigFromToolbar`) | `Unify` | Share `BackupExportSheet` / `BackupExportForm` (`DataSettings+macOS.swift:205-248` vs `DataBackupSettings+iOS.swift:330-371`), backup/restore password prompt & result messaging, and extract `SSHConfigImportAction` instead of duplicating `NSOpenPanel` `~/.ssh/config` import in both `DataSettings+macOS.swift:181-201` and `ServersView+macOS.swift:89-108`. | **−130** |
| **S06** | `Application/Rayon/Interface/Common/PickerSheets+macOS.swift:17-152` (`UURemoteSessionPickerSheet`) vs `Interface/Terminal/UURemoteSessionPickerView+iOS.swift:14-165` | `Unify` | Both wrap `UURemoteSessionList` with identical `Phase` state (`loading`/`loaded`/`failed`), `ending` confirmation alert, `load()`, and `end(_:)`. Merge into `UURemoteSessionList.swift` as a single `UURemoteSessionPickerSheet`. | **−95** |
| **S07** | `Application/Rayon/Interface/Shell/AppRouter+macOS.swift:271-343, 451-455` vs `ServerWorkspaceView+iOS.swift:19-28, 131-199` | `Unify` | Both files independently define `SessionOwner` / `SessionKind` and manually iterate all 5 session managers (`TerminalManager`, `FileTransferManager`, `EditorCenter`, `MonitorCenter`, `RemoteDesktopManager`) to group owners, count badges, look up titles, and close all sessions for an owner. Move `ActiveSessionDirectory` into `RayonModule` (and delete the `.terminals` / `end(for:)` aliases on `TerminalManager`). | **−95** |
| **S08** | `Application/Rayon/Interface/PortForwards/PortForwardView+macOS.swift:1-249` + `PortForwardEditor+macOS.swift:1-147` vs `PortForwardView+iOS.swift:1-319` | `Unify` | Share `PortForwardEditor` (`PortForwardEditorSheet` on macOS vs `PortForwardEditSheet` on iOS `PortForwardView+iOS.swift:178-318`), validation state, and toggle/copy-command actions. | **−95** |
| **S09** | `Foundation/RayonModule/Sources/RayonModule/RemoteDesktop/UI/RemoteDesktopCanvas.swift:200-341, 395-407` (UIKit) vs `:852-925, 963-973` (AppKit) | `Unify` | Extract shared `RemoteDesktopCanvasGeometry` struct for identical `aspectFitRect(framebuffer:bounds:)`, `normalizedPoint(location:in:framebuffer:)` (with 5% letterbox slop), cursor scaling rect, and 28pt scroll-tick accumulator loop. | **−65** |
| **S10** | `Application/Rayon/Interface/Settings/LicenseSheet+macOS.swift:1-60` vs `AgreementView+iOS.swift:1-58` + `LicenseView+iOS.swift:1-61`; plus version string formatting in `Welcome.swift:38-49`, `AboutSettings.swift:20-28`, `ContentView+iOS.swift:325-334` | `Unify` | Replace `AgreementView+iOS` + `LicenseView+iOS` + `LicenseSheet+macOS` with one shared `BundledDocumentSheet(resource:title:)`, and reuse `RXAppVersion.text` (`Welcome.swift:39`) in `AboutSettings` and `ContentView+iOS` instead of 3 separate `CFBundleShortVersionString`/`#if DEBUG` formatters. | **−50** |

#### A2. Dead Code: Zero-Caller Files, Types, Properties & Methods (`~405` Prod LOC Savable)

Verified via repo-wide `rg` across `Application/` and `Foundation/*` (excluding protocol witnesses and `@propertyWrapper` `projectedValue`):

| ID | Dead Code Location (`file:line`) | Action | Verification & Replacement Details | Est. LOC Delta |
| :--- | :--- | :--- | :--- | ---: |
| **D01** | `Application/Rayon/Extension/FilePicker+iOS.swift:1-94` | `Delete` | `FilePicker` (`13-49`) has **0 callers**; `FilePickerUIRepresentable` (`51-92`) has 1 caller (`FileTransferView+iOS.swift:64`) where SwiftUI's native `.fileImporter(isPresented:allowedContentTypes:[.item], allowsMultipleSelection: true)` is a 5-line drop-in (already used in `IdentityEditor.swift:212` and `DataBackupSettings+iOS.swift:134`). Delete entire file. | **−89** |
| **D02** | `Foundation/RayonDesign/Sources/RayonDesign/`:<br>- `Controls.swift:136, 179-188, 221-253` (`ButtonStyle.rxPlain`, `rxFieldBackground()`, `RXValueField`)<br>- `Form.swift:22, 33-36, 73-95` (dead `else` of `#available(macOS 15, iOS 18)`, `SwitchRow`)<br>- `Page.swift:124-165, 266-283` (`TableHeaderLabel`, `TableGroupRow`, `WidthKey`, `readWidth`)<br>- `Tokens.swift:41, 95, 128, 132-137, 142, 162, 165-170, 193` (`tableHeaderHeight`, `rxSidebarSelected`, `rxScrim`, `rxTerminal*`, `rxSectionLabel`) | `Delete` | **0 callers** anywhere in `Application/` or `Foundation/*` (note: overlaps with 1C-W02 if `RayonDesign` components are replaced wholesale; listed here with exact per-symbol lines for standalone dead-code pruning). | **−152** |
| **D03** | `Foundation/RayonModule/Sources/RayonModule/RemoteDesktop/UU/UULocalBridge.swift:27-33, 164, 188-197, 205-207` | `Delete` | `makeURL(action:deviceID:extra:)`, `cliStatus()`, `cliDeviceList()`, and `cliAssistStart(connectID:)` have **0 callers** anywhere in repo or tests; also `runCLI(_:timeout:)` (`:164`) accepts `timeout: TimeInterval = 15` and never uses it. | **−36** |
| **D04** | `Application/Rayon/Extension/View+iOS.swift:12-15, 39-57` + `EditorWorkspaceView+iOS.swift:20-35` + `AgreementView+iOS.swift:53-57` + `LicenseView+iOS.swift:56-60` | `Delete` | `View.expended()`, `View.createPreview(creation:)`, `EditorWorkspaceScreen`, and legacy `PreviewProvider` stubs have **0 callers**. | **−54** |
| **D05** | `Foundation/RayonModule/Sources/RayonModule/`:<br>- `Store/RayonStore+Server.swift:31-43` (`findSimilarMachine`)<br>- `Terminal/TerminalManager+Tabs.swift:108-117` (`tabGroups`)<br>- `PortForward/RDPortForward.swift:66-69` (`forwardReversed`)<br>- `Snippet/BatchSnippetExecContext.swift:145-147` (`safeAccessCompletedMachines`, `hasFailures`)<br>- `Terminal/GhosttyTerminfo.swift:23` (`cacheKey`) | `Delete` | Confirmed **0 callers** across all production and test targets via `rg`. | **−42** |
| **D06** | `Foundation/RayonTerminal/Sources/RayonTerminal/Configuration/SettingsLayout.swift:111-119` (`categoryOfKey`) + `Foundation/RayonSSH/Sources/RayonSSH/SFTPSession.swift:44` (`isRegularFile`) + `Application/Rayon/Application/RayonApp+macOS.swift:39` (`MainWindow.minimumSize`) + `MainView+macOS.swift:117-122` (dead `< macOS 15` branch) + `MenubarTool.swift:67-69` (`item(withKey:)`) + `StatusItem.swift:19, 67-69` (`key`, `deinit { debugPrint(...) }`) | `Delete` | Confirmed **0 callers** (`MainView+macOS.swift:41` hardcodes `minWidth: 940, minHeight: 600` instead of reading `MainWindow.minimumSize`; deployment target is macOS 15+ so `else` branch in `HiddenWindowTitle` is unreachable; `StatusItem.deinit` left a stray `debugPrint`). | **−32** |

#### A3. Verbose Boilerplate vs Data-Driven Swift & Legacy Pre-3.0 Shims (`~215` Safe + up to `~1,200` Legacy LOC)

| ID | Location (`file:line`) | Action | Simplification Details | Est. LOC Delta |
| :--- | :--- | :--- | :--- | ---: |
| **V01** | `Application/Rayon/Interface/Home/HomeView+iOS.swift:72, 117, 203-218` + `Foundation/RayonModule/Sources/RayonModule/Backup/LegacyBackup.swift:53-92` (`readPasted` / `importPasted`) | `Delete` | Undocumented v1.x/v2.x hidden long-press-on-Connect pasteboard importer (`importFromPasteboard()`). Zero UI discoverability, superseded by `.rayonbackup` / `~/.ssh/config` import, and explicitly removable under `AGENTS.md` (*"Breaking changes are allowed when they remove legacy weight"*). | **−60** *(+ −45 test LOC in `BackupTests.swift:333-373`)* |
| **V02** | `Foundation/RayonModule/Sources/RayonModule/RemoteDesktop/UI/RemoteDesktopStageView.swift:284-456` (`controlBar`, `touchControls`, `moreMenu`, `controls`) | `Simplify` | Touch and macOS control bars repeat identical `Menu`/`Button`/`Label` definitions for Display, Quality, View Only, Special Keys, Type Text, Clipboard, Refresh, and Official App across `#if os(iOS)` and `#else` branches. Share action builders and compose layout list per platform. | **−75** |
| **V03** | `Foundation/RayonModule/Sources/RayonModule/RemoteDesktop/UI/UURemoteSessionList.swift:70-74`, `FileTransferContext+Editing.swift:24`, `DataSettings+macOS.swift:267`, `DataBackupSettings+iOS.swift:292` | `Simplify` | Inline ad-hoc `RelativeDateTimeFormatter()` / `ByteCountFormatter()` allocations into existing `RXFormat` / `ByteCountFormatStyle`, and consolidate duplicated UTF-8 streaming prefix splitters (`TerminalContext.completeUTF8Prefix` `TerminalContext.swift:305-315` vs `TerminalInputDecoder.append` `TerminalCallbacks.swift:71-95`). | **−45** |
| **V04** | `Foundation/RayonModule/Sources/RayonModule/Identity/IdentityDraft.swift:164-176` (`differs(from:)`) | `Simplify` | `differs(from:)` manually OR-chains 8 field comparisons after calling `apply(to: identity)`. Since `RDIdentity` is `Equatable` and `apply(to:)` preserves `id`/`modified`/`lastRecentUsed`, `differs(from:)` reduces to `method != originalMethod \|\| apply(to: identity) != identity`. | **−12** |
| **V05** *(Optional Legacy Drop)* | `Foundation/RayonModule/Sources/RayonModule/`:<br>- `Storage/LegacyStoreImport.swift:1-561` + `LegacyStoreImport+Notice.swift:1-42`<br>- `Settings/LegacySettingsImport.swift:1-68`<br>- `Backup/LegacyBackup.swift:1-52` + `PreferencesBackup.swift:19, 61-66`<br>- `TerminalSettings.swift:59-87, 270-272` (`config.ghostty` migration) | `Delete` *(Policy Decision)* | Pre-3.0 upgrade & backup compatibility decoders (v2.4–v2.8 plist/JSON/AES-CBC/`RGCM1`/`wiki.qaq.rayon`/`config.ghostty`). Per `AGENTS.md` (*"Breaking changes are allowed when they remove legacy weight (old data formats, migrations, compatibility decoders)"*), once 3.0 upgrade window closes these 5 shims + their dedicated test files (`LegacyStoreImportTests` `368`L, `LegacySettingsImportTests` `108`L, `LegacyBackupTests` `66`L) can be deleted cleanly (tracked in 1C-W31 as well). | **−705 prod / −542 test** *(optional)* |

---

### 1D-b. Over-Abstraction & Leaky Boundaries ("review代码抽象")

#### B1. Complete Audit of All 15 Protocols in Repository

Every `protocol` across all 329 production Swift files was audited for production conformer count and necessity:

| Protocol (`file:line`) | Prod Conformers | Verdict & Concrete Action | Est. LOC Delta |
| :--- | :---: | :--- | ---: |
| `TerminalSessionSurface` (`TerminalContext.swift:21-27`) + `TerminalSurfaceBridge` (`RayonTerminalView.swift:109-133`) + `TerminalManager.Context: TerminalContext` (`TerminalManager.swift:66-84`) | **1** (`TerminalSurfaceBridge`) | **`Inline` / `Delete` (Obsolete Boundary!)** — Comment at `TerminalContext.swift:18-19` claims *"implemented in the apps over RayonTerminalView so RayonModule never links the renderer"*, **but `RayonModule` ALREADY links `RayonTerminal`** (`import RayonTerminal` in `TerminalManager.swift:8`, `AppSetting.swift:16`, `PreferencesBackup.swift:11`, `TerminalSettingsSync.swift`). Delete `TerminalSessionSurface`, delete `TerminalSurfaceBridge`, collapse `open class TerminalContext` + `final class TerminalManager.Context` into a single `final class TerminalContext` owning `RayonTerminalView` (plus `terminals` / `end(for:)` aliases at `TerminalManager.swift:90-93, 147-149`). | **−75** |
| `TerminalUIHandler` + `DefaultTerminalUIHandler` + `TerminalInterface` (`TerminalInterface.swift:12-34`) + `IOSTerminalUIHandler` (`TerminalContext+iOS.swift:45-53`) | **1** (`IOSTerminalUIHandler`; macOS never sets it!) | **`Inline` / `Delete`** — 34-line file + lock + default class + conformer class for a single `@MainActor` callback (`autoOpenInterface`) only used on iOS! Replace with `@MainActor public var onAutoOpen: ((TerminalContext) -> Void)?` on `TerminalManager.shared`. | **−42** |
| `HostKeyTrustHandler` (`HostKeyTrust.swift:92-96`) + `HostKeyTrustPrompt` (`Indicator.swift:247-251`) | **1** (`HostKeyTrustPrompt`) | **`Inline`** — Single-method `@MainActor` protocol whose sole production conformer is a 4-line class calling `Indicator.confirm(question)`. Replace `HostKeyTrust.handler: HostKeyTrustHandler?` with `HostKeyTrust.prompt: (@MainActor @Sendable (HostKeyQuestion) async -> HostKeyAnswer)?`. | **−18** |
| `FileTransferUIHandler` + `DefaultFileTransferUIHandler` + `FileTransferInterface` (`FileTransferInterface.swift:13-53`) + `MacFileTransferUIHandler` (`FileTransferContext+macOS.swift:13-30`) + `IOSFileTransferUIHandler` (`FileTransferContext+iOS.swift:15-39`) | **2** (`Mac…`, `IOS…`) | **`Simplify`** — Both conformers implement `presentError` and `requiresConfirmation` identically via `Indicator.error` and `Indicator.confirm`! Only `autoOpenInterface` (iOS) and `downloadCompleted` (iOS toast) differ, and all calls can live as simple `@MainActor` closures on `FileTransferManager.shared` (matching `PortForwardBackend.onError` / `onCreated` at `PortForwardBackend.swift:20-21` instead of inventing a 3rd callback pattern!). | **−55** |
| `VNCRFBClientDelegate` (`VNCRFBClient.swift:17-22`) | **1** (`VNCRFBDriver`) | **`Keep` or `Inline` *(if not replaced by RoyalVNCKit)*** — Clean internal seam allowing `VNCRFBTests` & `VNCLiveTests` to observe `VNCRFBClient` without spinning up a `RemoteDesktopSession`. | `0` |
| `StringColumn` (`Storage+Column.swift:24-36`) | **3** (`ForwardOrientation`, `Transport`, `RemoteDesktopProtocolType`) | **`Keep`** — Concise 12-line WCDB `ColumnCodable` default implementation shared by 3 `RawRepresentable<String>` enums. | `0` |
| `AnySettingKey` (`SettingKey.swift:28-31`) | **1** (`SettingKey<Value>`) | **`Keep`** — Minimal 4-line existential erasure required for heterogeneous `AppSettings.all: [any AnySettingKey]`. | `0` |
| `SettingsRecord` (`SettingsRecordSync.swift:16-25`) | **2** (`RDAppSettings`, `RDTerminalSettings`) | **`Keep`** — Clean internal generic constraint deduplicating push/pull reconciliation across the two synced settings tables. | `0` |
| `StoredRecord` & `RecordSecrets` (`StoredRecord.swift:15-55`) | **7** & **3** | **`Keep`** — Core WCDB + Keychain + CloudKit sync record contract. | `0` |
| `RemoteDesktopDriver` (`RemoteDesktopDriver.swift:19-59`) | **2** (`VNCRFBDriver`, `UURemoteDesktopDriver`) | **`Keep`** — Real multi-backend driver boundary (VNC vs UU Remote). | `0` |
| `VNCTransport` (`VNCStream.swift:13-23`) | **3** (`VNCConnection`, `SSHChannelTransport`, `MemoryChannel`) | **`Keep`** — Real transport polymorphism (TCP vs SSH `direct-tcpip` channel vs test buffer). | `0` |
| `AgentAlgorithm` (`SSHAgent.swift:189`) & `RSASignatureAlgorithm` (`SSHRSAKey.swift:18`) | **9** & **3** | **`Keep`** — Required by `swift-nio-ssh`'s static `keyPrefix`/`signaturePrefix` type-level design. | `0` |
| `TerminalPreviewRepresentable` (`TerminalSettingsView.swift`, internal) | **1** | **`Keep`** — Standard `NSViewRepresentable` / `UIViewRepresentable` platform alias. | `0` |

#### B2. Pass-Through Wrappers, Split State & Sentinel Dummy Objects (`~185` Prod LOC Savable)

| ID | Smell & Location (`file:line`) | Action | Root Issue & Concrete Fix | Est. LOC Delta |
| :--- | :--- | :--- | :--- | ---: |
| **A01** | **Duplicated SSH Connection Identity Key + Dead Stored `identity` Properties**:<br>- `Foundation/MachineStatusView/Sources/MachineStatusView/MonitorSession.swift:103, 113-116, 322-325, 412-420, 432-468`<br>- `Foundation/RayonModule/Sources/RayonModule/FileTransfer/FileTransferContext.swift:30, 126-128` + `FileTransferManager.swift:41` | `Unify` / `Delete` | `MonitorCenter.ConnectionKey` (`MonitorSession.swift:432-468`, 37 LOC) hand-rolls an incomplete copy of `SSHConnectionPool.key(for:)` (`SSHConnectionPool.swift:87-126`) — and **misses jump-host chain edits and auto-auth identity edits**! Meanwhile, `MonitorSession.identity` and `FileTransferContext.identity` are stored at init and **never read** for connecting (both lease from `SSHConnectionPool.shared`). Make `SSHConnectionPool.connectionKey(for:)` `public`, delete `MonitorCenter.ConnectionKey`, and delete unused `identity` stored properties on `MonitorSession` and `FileTransferContext`. | **−48** |
| **A02** | **Redundant Combine Relay Class `DesktopMenuState`**:<br>- `Application/Rayon/Application/RayonCommands+macOS.swift:142-170` | `Delete` / `Inline` | `DesktopMenuState` (29 LOC) subscribes to 4 `@Published` properties on `RemoteDesktopSession` (`$phase`, `$displays`, `$canAddDisplays`, `$viewOnly`) via Combine `.sink`s just to copy them into 4 `@Published` booleans! Pass `session` into a small `@ObservedObject` subview inside `CommandMenu("Remote Desktop")`. | **−25** |
| **A03** | **18 Sentinel `RDMachine()` / `RDIdentity()` / `RDPortForward()` Allocations Violating `AGENTS.md`**:<br>- `DashboardView+macOS.swift:82, 161, 165, 186, 192` & `DashboardView+iOS.swift:175, 179`<br>- `ServersView+macOS.swift:56` & `ServersView+iOS.swift:269`<br>- `ServerActions.swift:26` & `ServerActions+macOS.swift:17`<br>- `IdentityActions.swift:15` & `IdentityEditor.swift:261`<br>- `ServerWorkspaceView+iOS.swift:355`, `SidebarView+macOS.swift:208`, `PortForwardView+macOS.swift:166` | `Simplify` | Violates `AGENTS.md` (*"`Optional` instead of sentinel objects"*): views repeatedly write `store.machine(id) ?? RDMachine()`, allocating a dummy struct with a fresh `UUID()` and `Date()` on every SwiftUI body pass (5 times in `DashboardView+macOS.swift` alone!). Unwrap `guard let machine = store.machine(id)` once at the top of `body` (and pass `identity: RDIdentity?` in `IdentityEditor.save()` instead of `identity ?? RDIdentity()`). | **−35** |
| **A04** | **Pass-Through One-Liners & Split Lifecycles**:<br>- `Storage+Sync.swift:109-111` (`forgetSyncState()` just calls `removeAllSystemFields()`)<br>- `PortForwardContext.swift:41-49, 61-63` + `PortForwardBackend.swift:38-43, 50-56` (`@Published lifecycle` marked *"Views observe the backend's per-forward record, not this directly"* + dual `lifecycleHandler`/`terminationHandler` closures)<br>- `FileTransferContext.swift:32-35, 191-199` & `TerminalContext.swift:44-50, 347-356` (`processShutdown()` + `destroyedSession = true` two-step teardown repeated across every caller) | `Inline` / `Simplify` | Inline `forgetSyncState()`; fold `destroyedSession = true` into `shutdown()` so callers (`TerminalManager`, `FileTransferManager`, `BatchOutputView`) don't have to remember a 2-line ritual; simplify `PortForwardContext` -> `PortForwardBackend` reporting. | **−35** |
| **A05** | **Dual In-Memory LookupCaches on `RayonStore`** (`RayonStore.swift:75-109, 127-133, 453-488`) | `Simplify` | `RayonStore` maintains **both** 5 `[ID: Int]` position dictionaries (`machinePositions`, `identityPositions`, etc. — initialized twice: in `init` and in `didSet`!) **and** `workerSnapshot = Mutex(WorkerSnapshot)` holding `[ID: RDMachine]` + `[ID: RDIdentity]` dictionaries rebuilt on every `machines`/`identities` mutation (including `lastConnection`/`lastBanner` updates!). Consolidate dictionary indexing so `workerSnapshot` is updated without redundant double-indexing boilerplate. | **−42** |

---

### 1D-c. Over-Testing Review ("是否过度测试")

All **83 test files (`11,674` LOC)** across `Foundation/*/Tests/**`, `Application/RayonUITests/**`, and `Server/Telemetry/test/**` were read in full and classified.

**Overall Assessment**: The test suite in `RayonSSH` (`1,980` LOC), `MachineStatus` (`913` LOC), `Telemetry` (`708` LOC), `Server/Telemetry` (`428` LOC), `RayonTerminal` (`1,069` LOC), `Logger` (`207` LOC), and `RayonEditor` (`132` LOC) is **exceptionally high-signal** — testing real wire codecs, CVE-2019-6111 path traversal, NIO half-closure/window backpressure, MetricKit PII scrubbing, k-anonymity range differencing, and real Ghostty surfaces. Over-testing is concentrated in **`RayonModuleTests`**, where several files test trivial struct properties/defaults, mock-only wiring, UI string phrasing, or verbose unparameterized XCTest boilerplate.

#### C1. Suites to Delete, Consolidate, or Parameterize (`~635` Test LOC Savable; up to `~1,177` with Legacy Drop)

| Test File (`file:line`) | LOC | Classification & Action | Why Over-Tested & How to Slim Without Losing Coverage | Est. LOC Delta |
| :--- | ---: | :--- | :--- | ---: |
| `Foundation/RayonModule/Tests/RayonModuleTests/VNCRFBTests.swift:70-108` (`testRemoteDesktopDefaults`, `testRemoteDesktopSettings`) | 39 | **`Delete`** (Trivial DTO getter/setter test) | Lines `70-108` literally construct `var machine = RDMachine()`, assign 10 stored properties (`machine.vncPort = "5901"`, `machine.uuFPS = 144`, etc.), and `XCTAssertEqual` that Swift stored properties return the values assigned two lines above! Keep lines `110-989` (real DES, RFB wire, Raw/RRE/Hextile/ZRLE zip-bomb, ARD DH+AES, and security downgrade tests — note: if 1C swaps VNC to `RoyalVNCKit`, the RFB decoder tests retire with `VNCDecoders`). | **−40** |
| `Foundation/RayonModule/Tests/RayonModuleTests/RemoteDesktopSessionTests.swift:1-32` | 32 | **`Delete` / `Consolidate`** | Only tests that `RemoteDesktopSession(machine: RDMachine(), protocolType: .none)` starts `.idle`, sets `.failed` when `.none` connects, and sets `.closed` on `disconnect()`. Merge 10 lines into `VNCRFBTests` or `RemoteDesktopTouchInputTests` and delete file. | **−22** |
| `Foundation/RayonModule/Tests/RayonModuleTests/FileTransferPhaseTests.swift:1-26` | 26 | **`Delete`** (Trivial property assignment test) | Tests that `FileTransferContext.connectionPhase` starts `.idle` and `processShutdown()` sets `.closed`, `connected = false`, and `currentHint == "Connection Closed"` (brittle localized string check). | **−26** |
| `Foundation/RayonModule/Tests/RayonModuleTests/SSHStatusLineTests.swift:1-28` | 28 | **`Delete`** (Brittle UI string concatenation test) | Asserts exact `"ED25519 Key from Work (laptop)"` string formatting of a 4-line string-interpolation property `RDIdentity.signInDescription`. | **−28** |
| `Foundation/RayonModule/Tests/RayonModuleTests/PortForwardPresentationTests.swift:1-96` | 96 | **`Parameterize` / `Slim`** | 96 lines of repetitive XCTest assertions restating every `switch` arm's UI string in `PortForwardPresentation` (`"Connecting"`, `"Running"`, `"Could not connect"`, `"This Mac :port → server → target"`). Convert to 1 concise Swift Testing `@Test(arguments:)` table covering the non-trivial `(state, running)` matrix (`forwardRunning + !running -> .off`) and `commandPreview` placeholders. | **−60** |
| `Foundation/RayonModule/Tests/RayonModuleTests/TerminalSessionTests.swift:1-59` | 59 | **`Slim`** (Half tests a mock) | `RecordingSurface` (`45-58`) + `testBootstrapWritesOnlyThroughInjectedSurface` (`10-21`) only verifies that `TerminalContext` calls `surface.write` on a mock; once `TerminalSessionSurface` is inlined (**1D-b**), keep only the pure UTF-8 boundary & `usableSize` assertions (`23-42`) in `TerminalBridgeTests`, deleting `TerminalSessionTests.swift`. | **−45** |
| `Foundation/RayonModule/Tests/RayonModuleTests/UURemoteAdapterTests.swift:1-39` | 39 | **`Slim`** | Tests `UULocalBridge.authorizeURL`/`controlURL` query-item building and `RDMachine.isUURemoteDevice` enum equality (`transport == .uuRemote`). Trim trivial enum toggle checks; keep callback/URL roundtrip in `UURemoteFolderSyncTests`. | **−25** |
| `Foundation/RayonModule/Tests/RayonModuleTests/HostKeyQuestionTests.swift:1-47` | 47 | **`Slim` / `Consolidate`** | Asserts substring occurrences (`"Compare"`, `"Someone"`, `"Ed25519"`) in localized prose while `isWarning` boolean logic is what actually matters. Merge `isWarning` table (`libssh2Preferred` upgrade vs MITM warning) into `HostKeyTrustTests.swift` and delete separate file. | **−30** |
| `Foundation/RayonModule/Tests/RayonModuleTests/ServerUsernameTests.swift:1-89` + `QuickConnectAliasTests.swift:1-52` + `ServerDraftTests.swift:1-70` | 211 | **`Parameterize`** | Convert verbose multi-method XCTest setups for `sshLoginUsername`, alias matching, and `ServerDraft.problem` into compact Swift Testing `@Test(arguments:)` tables. | **−85** |
| `Foundation/RayonModule/Tests/RayonModuleTests/SSHCommandReaderTests.swift:1-225` | 225 | **`Parameterize`** | 22 separate `test*` functions constructing `SSHCommandReader("ssh ...")` and checking `remoteAddress`/`remotePort`/`username`. High-value parser coverage, but parameterized `@Test(arguments:)` cuts boilerplate in half while keeping every edge case! | **−95** |
| `Foundation/MachineStatus/Tests/MachineStatusTests/ProcParsersTests.swift:1-446` + `DarwinParsersTests.swift:1-139` | 585 | **`Parameterize`** | Keep 100% of `/proc` & Darwin parser fixtures, but collapse repetitive `formatKilobytes` / interface-filter / edge-case XCTest methods into `@Test(arguments:)` (and delete `formatKilobytes` tests if `W16`/`W33` replaces `formatKilobytes` with `ByteCountFormatStyle`). | **−90** |
| `Foundation/RayonModule/Tests/RayonModuleTests/AppSettingsSyncTests.swift:1-161` + `TerminalSettingsSyncTests.swift:1-147` | 308 | **`Consolidate`** | Both test the exact same `SettingsRecordSync<Record>` reconciliation state machine (`push`/`pull`/local-edit-wins-over-unapplied-remote) twice through `AppSettingsSync` and `TerminalSettingsSync`. Test the shared `SettingsRecordSync` state machine once + 1 thin wiring test per adapter. | **−90** |
| `BackupTests.swift:333-373` (`PastedImportTests`) *(+ optional pre-3.0 legacy test suites: `LegacyStoreImportTests.swift` `368`L, `LegacySettingsImportTests.swift` `108`L, `BackupTests.swift:266-331` `66`L)* | 45 *(+542)* | **`Delete` with V01 / V05** | `PastedImportTests` retires immediately when hidden pasteboard v1/v2 import (**V01**) is deleted; the remaining `542` LOC of legacy migration tests retire if pre-3.0 shims (**V05**) are dropped. | **−45** *(−587 w/ V05)* |

#### C2. High-Value Test Suites Explicitly Marked **KEEP** (Do Not Touch Coverage)
- **`RayonSSHTests` (`1,980` LOC)**: `SFTPSessionTests` (handle leak + CVE-2019-6111 traversal), `SSHForwardListenerTests` (NIO `Deinited NIOAsyncWriter` crash prevention), `SSHPrivateKeyTests` (all OpenSSH/PEM ciphers + bcrypt round DoS cap), `SSHTimeoutTests`, `SSHTransportTests`, `SSHBannerGateTests`, `SSHErrorWordingTests`, `SSHLiveTests`.
- **`RayonModuleTests` Core Persistence, Sync & Security (`~4,100` LOC)**: `StorageTests` (schema migrations, future-schema guard, corruption recovery, tombstone clock-skew stamping), `UnreadSecretsTests` (locked-keychain secret preservation — prevents catastrophic iCloud secret wipe!), `CloudSyncMappingTests`, `BackupTests` (AEAD encryption, wrong-password, rollback), `HostKeyTrustTests` (concurrent prompt coalescing & background-reconnect decline suppression), `KnownHostsTests`, `SSHConnectionPoolTests`, `LocalPseudoTerminalTests`, `PseudoTerminalIOTests`, `RemoteDesktopTouchInputTests`, `RemoteDesktopMailboxTests`, `RemoteDesktopKeymapTests`, `UURemoteFolderSyncTests`, `LibraryNoticeTests`.
- **`RayonTerminalTests` (`1,069` LOC)**: `ConfigurationTests` (verifies all 86 Ghostty catalog settings have localized titles/options and controls), `ConfigurationRuntimeTests` (undo coalescing, surface survival across config apply), `NativeTerminalTests` (OSC 52 clipboard sharing security gate), `TerminalBridgeTests`.
- **`TelemetryTests` (`708` LOC) & `Server/Telemetry/test` (`428` LOC)**: `ForbiddenPatternTests` (500-seed fuzzing against PII leaks), `ScrubberTests`, `SchemaSnapshotTests`, `CollectorTests`, `LevelTests`, `ingest.test.ts`, `dashboard.test.ts` (k-anonymity ≥10 range-differencing proof).
- **`LoggerTests` (`207` LOC), `RayonEditorTests` (`132` LOC), `MachineStatusViewTests` (`94` LOC), `RayonUITests` (`161` LOC)**.

---

### 1D-d. Over-Defensiveness Review ("是否过度防御")

| ID | Category & Location (`file:line`) | Action | Over-Defensive Pattern & Clean Replacement | Est. LOC Delta |
| :--- | :--- | :--- | :--- | ---: |
| **OD01** | **Double Back-to-Back 30s Combine Connection Wait**:<br>- `Foundation/RayonModule/Sources/RayonModule/FileTransfer/EditorWorkspace.swift:76, 112-120` (`EditorDocument.waitForConnection()`)<br>- `Foundation/RayonModule/Sources/RayonModule/FileTransfer/FileTransferContext+Editing.swift:46-55` (`readText(at:)`) | `Delete` | `EditorDocument.load()` awaits `waitForConnection()` (which constructs `$connected.combineLatest($processConnection).timeout(.seconds(30), scheduler: DispatchQueue.main).values`) and then **immediately** calls `context.readText(at: path)`, which runs the **exact same 10-line `$connected.combineLatest($processConnection).timeout(.seconds(30))` loop again**! Worse, `EditorDocument.waitForConnection()` doesn't even trigger `processBootstrap()` if disconnected, whereas `readText(at:)` does. Delete `EditorDocument.waitForConnection()` completely. | **−11** |
| **OD02** | **Triple-Repeated Trimming, Port Parsing & Fallback Defaults Across `ServerDraft` → `RDMachine` → `RDMachine+SSH` → `VNCRFBDriver`**:<br>- `ServerDraft.swift:79-91, 105-108, 114-136`<br>- `RDMachine.swift:145-147, 189-197, 200-202, 248-254`<br>- `VNCRFBDriver.swift:90, 112, 116`<br>- `RDMachine+SSH.swift:66` | `Simplify` | Ports (`remotePort`, `vncPort`) are stored as untyped `String`s on `RDMachine`, validated via `UInt16` in `ServerDraft.isPort`, trimmed on save, then re-parsed with `Int(remotePort) ?? 22` / `UInt16(machine.vncPort) ?? 5900` across 9 call sites; `sshUsername` is trimmed in `ServerDraft.apply` (`:120`) and trimmed *again* on every read in `RDMachine.sshUsernameOverride` (`:189`, called inside table/row `shortDescription`!); `connectionTimeout` is clamped with `max(5, ...)` in `RDMachine+SSH.swift:66` and `max(..., 10)` in `VNCRFBDriver.swift:116`. Normalize once on `ServerDraft.apply` / import boundaries and provide a single `RDMachine.vncPortNumber: UInt16` helper. | **−30** |
| **OD03** | **Locks Wrapping `@MainActor`-Only State**:<br>- `FileTransferInterface.swift:45-53` (`OSAllocatedUnfairLock<FileTransferUIHandler>`)<br>- `TerminalInterface.swift:26-33` (`OSAllocatedUnfairLock<TerminalUIHandler>`)<br>- `HostKeyTrust.swift:105-154` (`OSAllocatedUnfairLock<State>`) | `Simplify` | `TerminalInterface.uiHandler` is **only ever written at launch on `@MainActor` and only ever read in `TerminalContext.processBootstrap()` (`@MainActor`)**! `FileTransferInterface.uiHandler` is also **100% `@MainActor`** (`FileTransferManager` and `FileTransferContext` are both `@MainActor`, yet `IOSFileTransferUIHandler` in `FileTransferContext+iOS.swift:21, 34` and `MacFileTransferUIHandler` in `FileTransferContext+macOS.swift:26` defensively wrap every call in `Task { @MainActor in ... }`!). Making the callbacks `@MainActor` removes 2 `OSAllocatedUnfairLock`s, 2 `Default*` classes, and 4 redundant `Task { @MainActor in }` hops! (`HostKeyTrust` can likewise be `@MainActor` since it presents UI alerts.) | *(counted in B1 + **−20** in app handlers)* |
| **OD04** | **Redundant `DispatchQueue.main.async` / `MainActor.assumeIsolated` Hops When Already `@MainActor`**:<br>- `Application/Rayon/Interface/RemoteDesktop/RemoteDesktopStageView.swift:815-819` (`DispatchQueue.main.asyncAfter` for toast instead of cancellable `Task.sleep` — can clear a newer toast of the same text!)<br>- `Application/Rayon/Interface/Terminal/TerminalPage+macOS.swift:1049` & `TerminalView+iOS.swift` (`DispatchQueue.main.async` inside `@MainActor` view actions)<br>- `SettingObserver` (`AppSetting.swift:83-88`) & `RayonStore.swift:134-148` (`SettingKey.publisher` uses `.receive(on: DispatchQueue.main)` requiring `MainActor.assumeIsolated` in every subscriber) | `Simplify` | Replace `DispatchQueue.main.asyncAfter` toast timer in `RemoteDesktopStageView:815` with a `@State var toastTask: Task<Void, Never>?` (`Task.sleep`), which also fixes premature dismissal when the same notice fires twice within 2s. | **−15** |
| **OD05** | **Silent `try?` Error Swallowing on State Persistence (`229` prod `try?` occurrences audited)**:<br>- `CloudSync.swift:270, 282-283, 292, 429, 448` (`saveScopes`, `saveState`, `setFailedMerges`, `enqueueEverything`)<br>- `PreferencesBackup.swift:53, 57` (`try?` discarding real `DecodingError` / plist parse reason and throwing generic `"cannot be read"`)<br>- `UULocalBridge.swift:190, 196` & `Storage.swift:309-320, 396, 408` | `Simplify` | Most `try?` in `SFTPSession` cleanup/rollback paths (`SFTPSession.swift:153, 193-195, 217, 263, 289`) and `Task.sleep` cancellations are **legitimate**. However, `CloudSync.saveState` / `saveScopes` / `setFailedMerges` silently swallow disk write failures with `try?` without even logging to `Logger.syncEngine.errorFile` — if `sync-state.json` fails to write, every launch re-fetches the entire CloudKit zone silently! Log errors in a 4-line `writeJSON(_:to:)` helper on `CloudSync` (also deduplicating 4 `JSONEncoder`/`Data(contentsOf:)` sites in `CloudSync.swift:257-294`). | **−18** |
| **OD06** | **Paranoid Duplicate Bounds Check in `FileTransferContext+Editing.swift:61-75`**:<br>- `FileTransferContext+Editing.swift:61-64` AND `:72-74` | `Keep` *(Documented)* | Checks `editableSizeLimit` before download via `sftp.entry(at:).size` and again on `data.count` after download. Worth keeping (4 lines) because special files / growing logs can report `size == 0` or grow during download. | `0` |

---

### 1D.5 Executive Summary of Estimated LOC Reduction

*(Note: Estimates below exclude wholesale library replacements from Section 1C such as swapping `RayonModule/VNC` for `RoyalVNCKit` or deleting `RayonDesign` components, so double-counting is avoided during Phase 2 planning.)*

| Audit Dimension | Prod LOC Delta | Test LOC Delta | Total LOC Delta | Key Drivers |
| :--- | ---: | ---: | ---: | :--- |
| **1D-a. Cross-Platform Unification (`S01–S10`)** | −1,495 | 0 | **−1,495** | Unifying duplicated macOS/iOS Terminal, Editor, Batch Snippet, Remote Desktop list, Backup/SSH-Config import, UU Picker, Port Forward editor, & active-session directory |
| **1D-a. Dead Code Removal (`D01–D06`)** | −405 | 0 | **−405** | `FilePicker+iOS.swift`, zero-caller `RayonDesign` views/tokens, dead `UULocalBridge` CLI helpers, `findSimilarMachine`, `tabGroups`, `forwardReversed`, `categoryOfKey`, dead previews |
| **1D-a. Boilerplate & Safe Shim Slimming (`V01–V04`)** | −192 | −45 | **−237** | Hidden v1/v2 pasteboard importer (`V01`), `RemoteDesktopStageView` bar deduplication, UTF-8 stream splitter unification, `IdentityDraft.differs` |
| **1D-b. De-Abstraction & Sentinel Cleanup (`B1 + A01–A05`)** | −375 | 0 | **−375** | Collapsing `TerminalSessionSurface` + `TerminalSurfaceBridge` + `TerminalManager.Context`, replacing 1-conformer `TerminalUIHandler` / `HostKeyTrustHandler` / `FileTransferUIHandler` lock-boxes with `@MainActor` closures, unifying `MonitorCenter.ConnectionKey` with `SSHConnectionPool.key`, deleting `DesktopMenuState` & 18 `RDMachine()` sentinels |
| **1D-c. Over-Testing Consolidation (`C1`, excl. V01/V05)** | 0 | −590 | **−590** | Deleting trivial DTO getter/setter & phase/string tests (`VNCRFBTests:70-108`, `FileTransferPhaseTests`, `SSHStatusLineTests`), consolidating duplicate `SettingsRecordSync` tests, parameterizing `SSHCommandReaderTests` & `PortForwardPresentationTests` with Swift Testing `@Test(arguments:)` |
| **1D-d. Over-Defensiveness Cleanup (`OD01–OD05`)** | −94 | 0 | **−94** | Removing duplicate 30s Combine `waitForConnection()`, normalizing port/username trimming once at draft boundary, removing `@MainActor` lock-boxes & `asyncAfter` toast race, unifying `CloudSync` JSON state I/O |
| **Subtotal (Zero-Breaking-Change Safe Slimming)** | **−2,561** | **−635** | **−3,196** | **100% of features, settings & upgrade paths preserved** |
| **Optional: Pre-3.0 Legacy Migration Drop (`V05`)** | −705 | −542 | **−1,247** | Dropping v2.4–v2.8 `LegacyStoreImport`, `LegacySettingsImport`, `LegacyBackup`, and `config.ghostty` migration shims (`AGENTS.md` permitted) |
| **GRAND TOTAL (1D Standalone)** | **−3,266** | **−1,177** | **−4,443** | **~6.9% of entire tracked repo LOC before 1C library swaps** |

<!-- END SECTION: AUDIT-LOC-ABSTRACTIONS -->

---

<!-- SECTION: EXECUTION-BACKLOG -->
## 2. Atomic Execution Backlog & Commit Log

> **Subagent Execution Rules**:
> 1. Every row below MUST land as its own atomic commit (`type(scope): Plain English sentence stating what is true after the commit`, body explaining *why*), keeping 100% of user-facing features and settings intact (`AGENTS.md`).
> 2. Stage files explicitly (`git add <paths>`), never `git add -A` (keep untracked `.playwright-mcp/` unstaged).
> 3. Before committing any code item, verify it builds and passes relevant tests (`make build-macos`, `make build-ios`, `make test`, plus `make scan-license` when dependencies change and `make sync-localization && make check-localization` when UI strings change).
> 4. Immediately `git push origin main` after each verified commit and update this table with the commit SHA and `DONE` status.

| ID | Wave | Scope | Atomic Commit Plan (100% Feature Parity) | Audit Refs | Status | Commit SHA | Pushed |
| :--- | :---: | :--- | :--- | :--- | :--- | :--- | :--- |
| **T00** | W0 | `docs` | Establish comprehensive review task board, Phase 1 baseline metrics, and atomic execution plan (+ trash untracked dead leftover dirs `W01`) | `1A–1D`, `W01` | `DONE` | _self_ | `YES` |
| **T01** | W1 | `module` | Remove pre-3.0 v2.x legacy store, settings, backup, and hidden pasteboard compatibility decoders while keeping manual Ghostty config import and CloudKit UUID derivation intact | `W31`, `V01`, `V05` | `PENDING` | — | — |
| **T02** | W1 | `design`, `app` | Remove unused `RayonDesign` components/tokens, zero-caller dead helpers across modules, and `FilePicker+iOS.swift` (migrating iOS SFTP upload picker to native `.fileImporter`) | `W02`, `W19`, `D01–D06` | `PENDING` | — | — |
| **T03** | W1 | `module`, `app` | Collapse single-conformer `TerminalSessionSurface`/`TerminalSurfaceBridge`/`TerminalManager.Context` and UI handler lock-boxes into direct `@MainActor` types, unify `SSHConnectionPool` connection keys, drop `DesktopMenuState` & 18 dummy `RDMachine()` sentinels, and remove duplicate 30s editor waits & over-defensive trims | `1D-B1`, `A01–A05`, `OD01–OD05` | `PENDING` | — | — |
| **T04** | W1 | `tests` | Delete trivial DTO getter/setter & brittle UI-string tests, consolidate duplicate `SettingsRecordSync` tests, and parameterize parser/presentation test suites with Swift Testing `@Test(arguments:)` | `1D-C1` | `PENDING` | — | — |
| **T05** | W2 | `storage` | Batch Keychain `SecItemCopyMatching` (`kSecMatchLimitAll`) and `SecretPresence` SQLite queries into $O(1)$ startup/reload queries, skip Keychain IPC on non-secret machine updates, update `RayonStore` indexes incrementally, and wrap `CloudSync` remote merges in a single transaction | `UI-PERF-07`, `A05` | `PENDING` | — | — |
| **T06** | W2 | `terminal`, `module` | Pass raw UTF-8 `Data` directly from SSH/PTY/UU streams to Ghostty without intermediate `String` round-trips (eliminating 3 custom UTF-8 byte scanners & split-packet corruption), reuse a single 64 KB PTY read buffer, and streamline batch snippet output buffering | `UI-PERF-10`, `W28`, `V03` | `PENDING` | — | — |
| **T07** | W2 | `sftp`, `module` | Read and write remote editor files directly in memory via `Citadel` `SFTPClient.withFile` (removing temp-folder disk I/O) and throttle SFTP transfer progress updates to 20 Hz with a single snapshot publish | `UI-PERF-11`, `W29` | `PENDING` | — | — |
| **T08** | W2 | `editor`, `logger`, `ssh` | Make `CodeEditor` keystrokes $O(1)$ (detect indentation once on load; avoid per-keystroke 4 MB string equality & `NSTextStorage` copies), keep a persistent `FileHandle` in `LogStore`, and avoid `snprintf` allocations in `SSHConnectionPool` HMAC fingerprinting | `UI-PERF-09`, `UI-PERF-12` | `PENDING` | — | — |
| **T09** | W2 | `ssh`, `module` | Replace hand-rolled Ed25519 wire serializer with `Citadel`, migrate `SSHAgent` from blocking POSIX sockets to async `NIOPosix` Unix domain sockets, replace `SOCKS5Handshake` with `swift-nio-extras` `NIOSOCKS`, streamline PEM/SEC1 key parsing, and replace `abandoning(...)` with structured task groups | `W24–W28`, `V04` | `PENDING` | — | — |
| **T10** | W3 | `vnc`, `module` | Replace the 2,322-line hand-rolled VNC RFB/DES/ARD/zlib/decoder stack with `RoyalVNCKit` (`MIT`), switch `RemoteDesktopSession` from 1s clipboard polling `Timer` to event-driven pasteboard/activation notifications, fix toast/cursor/geometry quirks, and eliminate the 4× `"Connecting"` stage repetition | `W20–W23`, `VM-UI-14`, `UI-PERF-12`, `S09`, `V02`, `OD04` | `PENDING` | — | — |
| **T11** | W4 | `terminal-settings` | Replace monolithic `@Observable` `TerminalSettings.config` reads with per-key `@Observable` `SettingSlot`s ($O(1)$ slider/stepper invalidation), cache base `GhosttyThemeDefinition` configurations, move JSON persistence to a background serial queue, and deduplicate `set_font_size` surface actions | `UI-PERF-01`, `UI-PERF-03`, `W05` | `PENDING` | — | — |
| **T12** | W4 | `terminal-settings` | Replace hand-rolled CSS color tables, regex key normalizers, shortcut recorder keymaps, and `NotificationCenter` undo state machine with `libghostty-spm` (`ghostty_config_*`, `TerminalKey`, `TerminalColor`), `Color.Resolved`, `KeyboardShortcuts` (`MIT`), `UndoManager`, and `@Observable` `ConfigNavigation` | `W03–W07`, `W09`, `UI-PERF-04` | `PENDING` | — | — |
| **T13** | W4 | `settings` | Make Settings controls lazy: replace up to 256 inline `BlossomColorPicker`s with lightweight color swatch buttons + lazy `.popover`, mount `KeyRecorder` & action pickers lazily on `Keyboard`, remove 2-pass `Form` height bounce & 40-row search embedding, pre-index/debounce search, and make `About`/`Privacy`/`FontPicker` reads non-blocking | `UI-PERF-02`, `UI-PERF-04`, `W08` | `PENDING` | — | — |
| **T14** | W4 | `settings` | Fix all Settings UI/UX & HIG defects: align & compact `TerminalPreview`, pause its `SharedDisplayLink` when hidden/collapsed, fix box-drawing sample gap, remove duplicate `Restore Defaults…` & white table header corner on `Keyboard`, fix `FontPicker` `.leading` alignment & `ThemeGallery` popover placement, add proper field chrome to `CommitField`s, gate `Thickening amount`, remove double search bars & phantom `AXRow`, and fix Settings window restoration/zoom | `VM-UI-01`..`VM-UI-07`, `UI-PERF-06` | `PENDING` | — | — |
| **T15** | W5 | `design`, `app` | Replace `EmptyStateView` with native `ContentUnavailableView`, `RXButtonStyle` with native `.bordered`/`.borderedProminent`/`.borderless` styles, custom byte/rate/date loops with `ByteCountFormatStyle`/`RelativeFormatStyle`, and hardcoded pixel fonts with semantic Dynamic Type styles | `W11`, `W12`, `W16`, `W17`, `W33`, `UI-PERF-06` | `PENDING` | — | — |
| **T16** | W5 | `motion`, `monitor` | Eliminate animation twitching: remove unscoped container `.animation(..., value:)` modifiers, give `MonitorHistory` samples monotonic IDs so `Sparkline` advances without vertical morphing, delete `.rxRise` lazy-scroll flicker and `.rxPop()` bounce, and enforce `LC_ALL=C` in remote status probes | `UI-PERF-05`, `W33` | `PENDING` | — | — |
| **T17** | W5 | `shell`, `sheets` | Rebuild macOS main sidebar on native `List(selection:).listStyle(.sidebar)` (`AXOutline` + arrow keys + session name fallback), replace `PageToolbarSlots` `[AnyView]` + `TitleBarDoubleClick` with native unified `.toolbar`, unify modal sheets onto adaptive native `Form(.grouped)` sheets (no voids/clipping/double borders), and fix `HomeView` overflow & menubar focus ring | `W10`, `W13–W15`, `VM-UI-09`, `VM-UI-11`, `VM-UI-12`, `VM-UI-15`, `UI-PERF-06` | `PENDING` | — | — |
| **T18** | W5 | `servers`, `files` | Hoist `MonitorCenter`, `TerminalManager`, and `UURemoteAccount` observation out of per-row views ($O(1)$ row invalidation + cached group sorting), fix `Servers`/`Files`/`Identities`/`Port Forward` table column sizing & card clipping at `940×600`–`1024×678`, and unify `Dashboard` & `Snippets` tile button bars | `UI-PERF-08`, `VM-UI-10`, `VM-UI-13` | `PENDING` | — | — |
| **T19** | W5 | `ui` | Fix `TerminalPage` Snippets drawer toolbar jump (inline filter field), theme Terminal find bar & inactive split-pane cursors, stabilize iOS tab close widths, support `Include` in OpenSSH config import, and unify duplicated `+macOS`/`+iOS` Terminal, Editor, Batch Run, Remote Desktop, Backup, UU Picker, ActiveSessionDirectory, PortForwardEditor, and BundledDocumentSheet code | `VM-UI-08`, `VM-UI-14`, `UI-PERF-06`, `W30`, `S01–S10` | `PENDING` | — | — |

<!-- END SECTION: EXECUTION-BACKLOG -->

---

<!-- SECTION: QA-REVIEW-LOG -->
## 3. Independent Reviewer Subagent Gate (`cua-driver` UI/UX + Performance + Code/Architecture)

> **Mandatory Sign-Off Protocol (Zero-Defect Exit Gate)**
> After implementation waves complete, an independent Reviewer Subagent (fresh context) audits the entire application across **all 6 dimensions below**. If **any** defect is found—whether a code smell, remaining wheel, missed optimization, or a visual/UI/UX design flaw spotted via `cua-driver`—fix subagents execute atomic fixes (`commit` + `push`) and re-run a new Reviewer Subagent round until `VERDICT: PASS (0 issues)`.

### Multi-Dimensional Review Rubric

1. **Computer-Use Live UI/UX & Visual Design Audit (`cua-driver` in `rayon-qa` + `apple-hig`)**:
   - Inspect live PNG screenshots + AX trees across **every route, every Settings category/subpage, search, popovers, modal sheets, context menus, split panes, empty states, and minimum window sizes (`940×600` main / `720×480` settings)**.
   - Check visual hierarchy, alignment, padding/inset symmetry, typography & Dynamic Type, truncation/clipping, horizontal/vertical scrollbar leaks, Light & Dark contrast, native control affordances, focus ring behavior, keyboard navigation (`AXOutline`, Tab, Esc, Cmd+F, Cmd+,), and UX friction.
2. **Motion & Animation Smoothness Audit**:
   - Verify zero layout jumps on drawer/tab/page toggles, zero unintended container spring collisions, smooth chart updates, and zero idle `DisplayLink`/GPU draw calls when previews or views are hidden/inactive.
3. **Quantitative Performance Verification (`Bench+macOS.swift` + `sample` + Interactive Latencies)**:
   - Re-run `RAYON_BENCH_SETTINGS=3`, `RAYON_BENCH_SEED=1 RAYON_BENCH_PAGES=3`, and `RAYON_BENCH_FILES=5000` in `rayon-qa`, plus interactive `cua-driver` timing on `Colors › Palette` (256 colors), `Keyboard`, `Search`, and slider edits. Compare directly against Section 1A baseline tables and verify main-thread stalls are eliminated.
4. **De-Wheeling Completeness & Feature Parity**:
   - Verify all targeted hand-rolled wheels (`W01`–`W33`) are cleanly replaced by mature libraries / native frameworks while **100% of user-facing features and settings remain intact and functional**.
5. **Code Slimming, Abstraction, Testing & Defensiveness Quality**:
   - Measure final prod + test LOC vs baseline (`64,164` LOC); verify zero single-use pass-through abstractions, zero dummy `RDMachine()` sentinels, clean parameterized high-signal tests, and zero silent error-swallowing or lock-wrapped `@MainActor` anti-patterns.
6. **Build, Concurrency, Security, License & Localization Hygiene**:
   - `make build-macos`, `make build-ios`, `make test`, `make scan-license`, and `make check-localization` all pass with zero errors; `git status` is clean and all atomic commits are pushed to `origin/main`.

### Review Rounds Log

- **Round 0 (Baseline — Subagent 1A)**: Recorded quantitative `Bench` + `sample` baseline and 15 live UI/UX/animation defect clusters (`[VM-UI-01]`..`[VM-UI-15]`) in Section 1A.
- **Round 1 (Post-Implementation Full Review)**: `PENDING`

<!-- END SECTION: QA-REVIEW-LOG -->
