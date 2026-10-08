# Refreshing the Ghostty Config catalog

The application bundles JSON and does not require Bun or a network connection at runtime.
The current snapshot is `zerebos/ghostty-config@fa7489fdb50015571d15375c2a3806f2ba1f6bf3`.

In a disposable checkout of that revision, copy `export-native.ts` to the root and
set `tsconfig.json` paths `$lib/*` to `./src/lib/*` and `$app/environment` to
`./environment.ts`. Create `environment.ts` containing `export const dev = false;`.
Run `bun export-native.ts` and redirect stdout to
`Foundation/RayonTerminal/Sources/RayonTerminal/Configuration/Resources/catalog.json`.
Review the schema and licenses before updating; run the RayonTerminal package tests.
