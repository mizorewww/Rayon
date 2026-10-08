# Rayon

A server monitor tool for linux based machines using remote proc file system with script execution. Available for macOS 13+ & iOS 15+.

The project has completed my requirements without serious defects and is now archived. If there are minor issues, please consider fixing them yourself. If there are serious problems, please consider writing me an email. (I do fix them)

**The App Store Package is now sold to 3rd developer because our Developer Program has expired. It does NOT keep relation to this repository anymore.**

## Building on macOS

Install the full Xcode application and select its developer directory. Command Line
Tools alone are not sufficient. Swift 6.2 or later is required by the Ghostty
dependency (Xcode 26 or later). Open `App.xcworkspace` and select the `Rayon` scheme
for the macOS app; `mRayon` is the separate iOS app.

For a local build without the original author's signing certificates:

```sh
bash Workflow/Scripts/build-macos.sh
bash Workflow/Scripts/build-macos.sh Release
```

Both commands build a universal `arm64` / `x86_64` application. The output is
`DerivedData/Build/Products/Debug/Rayon.app` or
`DerivedData/Build/Products/Release/Rayon.app`. Override `DERIVED_DATA_PATH` to use
another build directory.

To build Release and install it to `/Applications` in one step:

```sh
bash Workflow/Scripts/install-macos.sh
```

The script uses Xcode ad hoc signing for local execution. These are locally signed
applications, not notarized distribution packages. Configure your own team, signing
identity and provisioning profile before distribution; changing signing identity can
also affect access to existing Keychain items.

## Terminal

The macOS interactive SSH terminal and batch-command output use
`Foundation/RayonTerminal`, backed by
[libghostty-spm](https://github.com/Lakr233/libghostty-spm/) (exact version pin).
This requires **macOS 13+**. The iOS app still uses the legacy XTerminalUI package.

Run the terminal package tests (they briefly open native terminal windows; no SSH
connection or credential store is used):

```sh
swift test --package-path Foundation/RayonTerminal
```

On macOS, **Settings** in the sidebar contains General, Connection and the full
Ghostty configuration editor in one page. See
[Foundation/RayonTerminal/CONFIGURATION.md](Foundation/RayonTerminal/CONFIGURATION.md)
for coverage and application boundaries.

## Known security issues

This repository is archived with the following unresolved issues. Do not use it
with credentials you cannot afford to lose.

- **No host-key verification**: `NSRemoteShell.m` records the server fingerprint
  but never validates it against trusted host keys, so connections are open to
  man-in-the-middle attacks.
- **Weak credential encryption**: `Foundation/RayonModule/Sources/RayonModule/Utils/AES.swift`
  uses AES with the IV equal to the key and no authentication tag. In Debug
  builds the key is derived from the machine serial number; in Release builds a
  failed Keychain write can leave data encrypted under a non-persistent key.
- **Fragile data import**: `RayonStore.overrideImport` cannot distinguish missing
  data from decryption failure and may overwrite undecryptable data.

## Preview

![Preview](./Resources/Preview.png)
![Preview+iOS](./Resources/Preview+iOS.jpeg)

## Features

- [x] **free and open source**
- [x] libssh2 capable host connections
- [x] Linux proc file system status information
- [x] authenticate with password, key, etc...
- [x] native Ghostty terminal on macOS; xterm terminal on iOS
- [x] Port Forward support
- [x] code snippet with batch execution
- [x] Nvidia GPU status monitor
- [x] Running cat for macOS app

## License

[MIT License - Lakr's Edition](./LICENSE)

## Contributor

Made with love by [@Lakr233](https://twitter.com/Lakr233) along with his friends [@__oquery](https://twitter.com/__oquery) [@zlind0](https://github.com/zlind0) [@unixzii](https://twitter.com/unixzii) [@82flex](https://twitter.com/82flex) [@xnth97](https://twitter.com/xnth97) [@misakicoca](https://twitter.com/misakicoca) [@NyaaLyn](https://twitter.com/NyaaLyn)

---

Copyright © 2022 Lakr Aream. All Rights Reserved.
