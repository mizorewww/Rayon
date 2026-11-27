# Terminal settings in Rayon

Rayon's single **Settings** holds General, Connection, every terminal category
and About in one native SwiftUI view: a sidebar list and a grouped `Form` on
macOS, a `NavigationStack` of lists and forms on iOS, with one search across
all of it. There is no web view, JavaScript runtime or downloaded font.

## The file

The terminal settings are one Ghostty configuration file, `config.ghostty`, in
the app's Application Support folder. Settings changes it one key at a time;
comments, blank lines, keys it does not know and their order stay as written,
so the file also works in Ghostty and can be edited by hand. A change is
applied to every open terminal about a quarter of a second after the last edit,
once libghostty accepts both the light and the dark variant, and only then
written. A change Ghostty rejects is shown with Ghostty's diagnostic and
neither applied nor saved. Undo and Redo cover Settings' own changes.

Settings kept the earlier way (a JSON snapshot in the user defaults) move into
the file on first launch. The settings backup (`.rayonsettings`) carries the
file; restoring one applies it at once. iCloud sync carries every key except
the ones that belong to a device (font size, window padding).

## The model

- `settings.json`: every Ghostty option (200), with its name, documentation,
  default, platforms and input type, derived from
  [zerebos/ghostty-config](https://github.com/zerebos/ghostty-config/tree/fa7489fdb50015571d15375c2a3806f2ba1f6bf3)
  (Apache-2.0). `SettingControlKind` maps each to a native control: `Toggle`,
  `Slider`, number field with `Stepper` and presets, `Picker` (segmented when
  short), BlossomColorPicker colors, lists, flag sets, linked pairs, durations,
  lengths and byte counts; fonts, theme, palette, shortcuts and code point
  maps have editors of their own.
- `SettingsLayout`: the categories and groups. The categories Rayon's terminal
  reads hold exactly `RayonTerminalConfiguration.supportedKeys` and `theme`;
  every other option is under **Ghostty App**, kept in the file without effect.
  A test checks that every option appears exactly once.
- Themes: GhosttyTheme's catalog plus `themes.json`, the iTerm2-Color-Schemes
  themes it does not ship (633 in all), with one theme or one each for light
  and dark appearance.
- Shortcuts: Ghostty's defaults until the list is changed; then the file holds
  `keybind = clear` and the whole list, so a deleted default stays deleted.
  Window, tab and split actions are not shown, since Rayon manages those.

## Applying

`RayonTerminalConfiguration` builds what terminals get: Rayon's base (its
defaults and the unbinding of Ghostty's own search keys, which Rayon's find
bar replaces), the theme's colors, the supported keys from the file, then the
app's Copy on Select and Clipboard Sharing preferences. Existing surfaces, SSH
backends and scrollback stay alive; fractional font sizes stay fractional;
toolbar zoom survives a view's reappearance.

The preview above the terminal categories is a real `RayonTerminalView`,
connected to nothing, showing a fixed ANSI sample with the applied settings.

## Validation

`swift test --package-path Foundation/RayonTerminal` covers reachability of
every option, themes, file preservation, apply/reject/undo, legacy migration,
shortcut semantics, compound values and live surface/font continuity.

Data refresh instructions live in `Workflow/Scripts/GhosttyConfig/README.md`.
