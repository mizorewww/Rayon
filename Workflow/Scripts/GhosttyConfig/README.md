# Refreshing the terminal settings data

The app bundles JSON and needs neither Bun nor a network connection at runtime.
The current snapshot is `zerebos/ghostty-config@fa7489fdb50015571d15375c2a3806f2ba1f6bf3`.

1. In a disposable checkout of that revision, copy `export-native.ts` to the root
   and set `tsconfig.json` paths `$lib/*` to `./src/lib/*` and `$app/environment`
   to `./environment.ts`. Create `environment.ts` containing
   `export const dev = false;`. Run `bun export-native.ts > catalog.json`.
2. List the theme names GhosttyTheme ships (`GhosttyThemeCatalog.allThemes`, one
   name per line) into `ghosttytheme-names.txt`.
3. Run
   `python3 derive-settings.py catalog.json ghosttytheme-names.txt Foundation/RayonTerminal/Sources/RayonTerminal/Configuration/Resources`.
   It writes `settings.json` (every option, in the upstream category order, with
   web-only widget fields removed) and `themes.json` (the themes GhosttyTheme
   does not ship).
4. `export-keybinds.ts` produces `keybindings.json` the same way.

Review the schema and licenses before updating, then run the RayonTerminal
package tests: they check that every option in `settings.json` is reachable in
Settings exactly once.
