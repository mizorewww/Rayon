# Terminal configuration in Rayon

Rayon's terminal is Ghostty (libghostty, through `libghostty-spm`). Its settings
are one Ghostty config file, `config.ghostty`, in the app's Application Support
folder (`RayonTerminalConfiguration.fileURL`).

**Settings → Terminal** edits the keys people change most, over a live preview
that is a real, unconnected Ghostty terminal showing a fixed sample:

| Setting | Ghostty key |
| --- | --- |
| Theme | `theme` (any of the themes bundled with `GhosttyTheme`) |
| Background opacity | `background-opacity` |
| Font, size | `font-family`, `font-size` |
| Cursor style, blink | `cursor-style`, `cursor-style-blink` |
| Copy on select, clipboard sharing | app preferences, rendered as `copy-on-select`, `clipboard-read`, `clipboard-write` |

**Open in Editor** opens the whole file in Rayon's editor for everything else
Ghostty supports (keybindings, palette, padding, scrollback, …). A change from
either place is validated by Ghostty before it is saved; a rejected file is not
saved and the reason is shown. Open terminals take the change at once and keep
their scrollback.

How the file is applied:

- `theme = Name` or `theme = light:A,dark:B` is expanded from the bundled theme
  catalog, so every theme works offline. Without one, Ghostty's
  Alabaster/Afterglow pair is used.
- The file's own lines come after the theme, so an explicit colour wins.
- `copy-on-select`, `clipboard-read` and `clipboard-write` follow the app's
  clipboard preferences; the file's values for them are ignored.
- SSH, the local shell and UU Remote own the terminal's process: Ghostty never
  starts one, whatever `command` says.

`TerminalConfigurationSync` exposes the file's keys to iCloud sync.
