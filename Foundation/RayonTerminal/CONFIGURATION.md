# Native Ghostty Config in Rayon

Rayon's **Terminal Configuration** sidebar item opens a native SwiftUI page inside
the existing main window. The **Setting** page also has a prominent entry card.
The category list is embedded without a second navigation container; the optional
live preview starts collapsed to fit the main window and can be shown from the toolbar.
The editor targets macOS 13 and Swift 6 and has no web view, JavaScript runtime,
web service, or downloaded font dependency.

The catalog is a pinned adaptation of
[zerebos/ghostty-config](https://github.com/zerebos/ghostty-config/tree/fa7489fdb50015571d15375c2a3806f2ba1f6bf3).
It contains 200 settings, 11 categories, 633 themes, 17 widget kinds, and 83
keybinding action definitions. Bundled licenses cover the Apache-2.0 upstream
editor data, MIT theme data, and MIT Ghostty icon layers.

## Coverage

| Upstream capability | Native implementation |
| --- | --- |
| Full registry and category navigation | Data-driven settings and groups; test checks every setting occurs exactly once |
| Search and navigation | All-token matching across key, title, category, group and documentation; categorized results, highlighted titles, jump to setting, back/forward |
| Setting controls | Boolean, text, numeric/stepper, range, dropdown/pill, color, custom preset, repeatable/reorder, feature toggles, linked numbers, scroll multipliers, unit numbers, compound duration, theme, palette |
| Metadata and help | Platform/version/deprecation information, inline notes, documentation popovers and reference links |
| Theme selection | Searchable swatches; separate light/dark themes; custom names/paths preserved; theme selection does not write individual colors |
| Colors and palettes | Explicit override > theme > default; individual reset; 16/256 palette editor with sparse index export |
| Keybindings | Add/edit/multiselect delete/reset; modifier/prefix switches, up to four builder sequence steps, all 83 action definitions, typed arguments, raw escape hatch, canonical duplicate and validation diagnostics |
| Font playground | Installed/custom family, 4–60 pt in half-point increments, bold/italic, editable Unicode/Nerd Font sample; separate from configuration |
| Live previews | Theme, foreground/background, selection, cursor and icon layers; semantic terminal output redraws on color changes; preview can be hidden/minimized |
| Interactive terminal preview | In-memory files/directories; 16 commands, quoted arguments, conditional chains, completion, history, native text editing, interrupt/clear |
| Import/export | Paste text/share URL or choose file; preview merge before import; selectable export text, copy and native file exporter; default differences only |
| Sharing | Upstream-compatible UTF-8/base64url `#share=` links, selectable settings, system sharing, plain-text fallback above 1,800 URL characters |
| Reset/history | Individual/all reset; configuration undo/redo added alongside navigation history |
| Custom settings | Unknown keys and repeated values retained; native enhancement over upstream's lossy unknown-key handling |
| Persistence | Versioned complete JSON snapshot, independent of lossy export; legacy text migration; unsaved draft retained while reopening the editor in the same process |

The simulator supports `cat`, `cd`, `clear`, `date`, `echo`, `git`, `grep`,
`help`, `hostname`, `ls`, `mkdir`, `pwd`, `rm`, `touch`, `uname`, `whoami`.
It never launches a process, touches real files, or sends data to an SSH session.
Its sample files, curated git output, and native line wrapping are adapted for
Rayon rather than byte-identical copies of the web demonstration. The normal
AppKit input field provides selection, cursor movement, deletion, and editing.

## Applying configuration

Draft edits update previews immediately. **Save & Apply** validates both theme
variants with libghostty before updating the shared controller. Existing surfaces,
SSH backends, callbacks, and scrollback remain alive. Future interactive and batch
surfaces use the saved configuration. Fractional font sizes remain fractional.
Legacy toolbar zoom still works and survives a view's reappearance; explicitly
applying a configuration resets the surface to its configured font size.

`RayonTerminalConfiguration.supportedKeys` and `supportedActions` are the explicit
embedded-terminal application boundary. Other options remain editable and
exportable and are marked as standalone Ghostty settings. Process startup,
shell integration, GTK/Linux application integration, standalone window/tab
management, update behavior, app icons, custom includes, and global shortcuts
remain owned by their respective host application. Importing them cannot replace
Rayon's SSH transport. Unknown/custom theme paths are retained for export;
only bundled themes are materialized by the embedded runtime. Clipboard read/write
confirmation remains enforced by the existing native terminal delegate.

Rayon keeps its legacy defaults until explicitly changed. Internally, an explicit
value is retained even when equal to the upstream default, because that default
may differ from Rayon's (for example font thickening). Export still removes values
equal to the Ghostty Config catalog default. Reset removes the explicit override.
Deleting a default keybinding follows upstream export semantics: use an explicit
`trigger=unbind` entry when the exported configuration must disable it.

## Validation and review

`swift test --package-path Foundation/RayonTerminal` covers catalog completeness,
import merge/rollback, repeated values, palette diffs, Unicode sharing, theme
precedence, keybinding diagnostics, compound duration and scroll codecs, simulator
isolation, complete persistence, and live native surface/font continuity. It also
retains the earlier UTF-8/output buffering/clipboard/worker teardown regressions.

Both `bash Workflow/Scripts/build-macos.sh` and its `Release` variant build
arm64 + x86_64 with deployment target macOS 13. Compilation was verified using
Xcode 27 beta / Swift 6.4. Runtime checks ran on the available arm64 host; an Intel
Mac and a macOS 13 installation have not been exercised directly.

An independent subagent reviewed the upstream scope and the implementation.
Its persistence, fractional-font, scroll-label, bare-plus, and view-reappearance
findings were fixed and covered by regression tests. Native UI checks exercised
theme selection/recoloring, the keybinding list/builder and simulated command
entry, and corrected a clipping issue and bundled-icon loading.

For an isolated native UI harness, run:

```sh
bash Workflow/Scripts/build-configuration-preview.sh
```

This creates `DerivedData/RayonConfigurationPreview.app` with a separate bundle
identity and preference domain, without opening Rayon's account store. The
application binaries produced by the main build script are ad hoc signed and
strictly verified, including nested code and both architectures. Both main app
configurations were launched through LaunchServices on the arm64 host, and the
Release configuration page was opened inside the main window from the sidebar.
The final Setting-card routing correction compiles in both configurations and was
reviewed, but its repeat-navigation GUI check is pending: the subsequent launch
waited in `SecItemCopyMatching` for system keychain access before creating a window.
Developer ID
distribution signing, notarization, external SSH-server end-to-end interaction,
and every individual standalone Ghostty setting are outside these local checks.

Catalog refresh instructions live in `Workflow/Scripts/GhosttyConfig/README.md`.
