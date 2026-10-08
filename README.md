# Rayon

A server monitor tool for linux based machines using remote proc file system with script execution. Available for macOS 12+ & iOS 15+.

The project has completed my requirements without serious defects and is now archived. If there are minor issues, please consider fixing them yourself. If there are serious problems, please consider writing me an email. (I do fix them)

**The App Store Package is now sold to 3rd developer because our Developer Program has expired. It does NOT keep relation to this repository anymore.**

## Building on macOS

Install the full Xcode application and select its developer directory. Command Line
Tools alone are not sufficient. A Swift 6-capable Xcode is required. Open
`App.xcworkspace` and select the `Rayon` scheme
for the macOS app; `mRayon` is the separate iOS app.

For a local build without the original author's signing certificates:

```sh
bash Workflow/Scripts/build-macos.sh
bash Workflow/Scripts/build-macos.sh Release
```

Both commands build a universal `arm64` / `x86_64` application. The output is
`DerivedData/Build/Products/Debug/Rayon.app` or
`DerivedData/Build/Products/Release/Rayon.app`. Override `DERIVED_DATA_PATH` to use
another build directory. The script works from any working directory and does not
modify the project's distribution signing settings.

Verified on 2026-10-08 with Xcode 27.0 (27A5209h), Swift 6.4 and an arm64
macOS 27.2 host: both Debug and Release builds succeeded in Swift 6 language mode,
and `lipo` confirmed both architectures in each executable. Both shared packages
also resolved their dependencies independently. No application launch, SSH
integration, Intel runtime, macOS 12 runtime or iOS build was tested. Existing
warnings include missing app icons, deprecated APIs and legacy SDK actor-isolation
warnings. Explicit Combine imports were added to four timer-using
views to remove the current compiler's implicit-import warnings.

These are unsigned build artifacts, not notarized distribution packages. Configure
your own team, signing identity and provisioning profile before distribution;
changing signing identity can also affect access to existing Keychain items.
Use disposable test credentials: the legacy Debug encryption is derived from the
machine serial number, not a random secret. Release also has unresolved security
issues described below. Building successfully is not a security or runtime audit.

## Swift 6 migration

The macOS app uses `SWIFT_VERSION = 6.0`. Its ten local Swift dependencies use
Swift tools 6.0 and the default Swift 6 language mode: RayonModule, MachineStatus,
MachineStatusView, PropertyWrapper, Keychain, XMLCoder, Colorful, SymbolPicker,
CodeEditorUI and XTerminalUI. Actual Release compiler invocations were checked
for `-swift-version 6` for all eleven modules. The macOS app deployment target
remains 12.0. The Objective-C NSRemoteShell and binary CSSH targets are unchanged.
Packages not in the macOS dependency graph and the iOS app target were not migrated
or validated; shared package changes will also affect a future iOS build.

This is a behavior-preserving language migration. SSH operations, encryption and
storage formats, confirmation shortcuts, retry counts, blocking waits and GCD
queue scheduling retain their existing logic. Value types with Sendable storage
now explicitly conform to Sendable. Local `nonisolated(unsafe)` declarations
preserve legacy singleton, callback and shared-storage boundaries without claiming
that those types are thread-safe. Terminal/editor forwarding methods retain their
synchronous nonisolated interface.

UI construction sites have explicit main-actor boundaries. The `mainActorUI`
helper preserves the original synchronous main-thread/zero-delay path and delayed
GCD path; `MainActor.assumeIsolated` checks the executor only on that established
main-thread path. The event-monitor bridge similarly uses
[AppKit's main-thread callback contract](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html).
These checks add no task or queue hop. Legacy model callbacks
continue to use their existing helper without imposing actor isolation on models.

Run the focused scheduling regression check without launching the app or accessing
credentials:

```sh
python3 Workflow/Scripts/verify-swift6-scheduling.py
```

It compiles the actual four helper implementations in Swift 6 mode and verifies
synchronous ordering, background enqueueing, delayed execution and main-thread
callback delivery. All four passed on the host above. An independent subagent
review checked the migration diff for behavior changes; this is not a full runtime
or data-race audit. The [Swift migration guide](https://github.com/swiftlang/swift-migration-guide/blob/main/Guide.docc/CommonProblems.md)
describes the limitations of these incremental compatibility boundaries.

## Platform migration review

The bundled SSH framework already contains Apple Silicon and Intel macOS slices;
disabling arm64 or requiring Rosetta is not necessary. Two shared package manifests
point to the actual `External/NSRemoteShell` directory instead of relying on
workspace dependency overrides.

Independent subagent review identified these follow-up priorities. They are
existing issues, not fixes included in the build compatibility patch:

1. **Before using real credentials:** `NSRemoteShell.m` records a server fingerprint
   but the authentication paths do not validate it against trusted host keys.
   Add shared host-key verification before authentication, including monitoring,
   terminal, SFTP, batch commands and forwarding; reject changed keys.
2. **Protect stored credentials:** in `Utils/AES.swift`, the Release initializer
   assigns a new key before Keychain persistence succeeds. A failed write can
   leave encryption using a nonpersistent key. Only activate a successfully
   persisted key. Replace fixed-IV, unauthenticated encryption with a versioned
   authenticated format and random keys/nonces, retaining a legacy reader.
3. **Make data migration recoverable:** `RayonStore+Util.swift` conflates missing
   data with decryption/decoding failure. Preserve old ciphertext, distinguish
   these states and block overwrites when existing data cannot be decrypted.
   Do not change signing, encryption format and SSH dependencies in one migration.
4. **Verify forwarding behavior:** `NSLocalForward.m` passes `&sin` rather than
   its local address buffer to `accept`, and calls `getpeername` on standard input.
   Correct this separately and test actual bidirectional connections.
5. **Modernize dependencies and concurrency incrementally:** record the source,
   crypto backend, build flags and hashes of the bundled libssh2 1.10.0 artifact
   before replacing it. Establish SSH interoperability tests. Swift 6 language
   migration is complete for the macOS build, but legacy concurrency boundaries
   remain. In a separate behavior-changing project, audit ownership and remove
   unsafe exemptions, isolate UI state and SSH sessions, and replace blocking
   WebKit/semaphore bridges with bounded, cancellable asynchronous operations.
6. **Platform acceptance:** exercise terminal, SFTP, monitoring, forwarding,
   reconnection, Keychain failures and host-key changes on real macOS systems.
   Verify iOS and Apple Silicon simulators separately before claiming support.
   Review multi-window presentation and WebKit file access. Restore the missing
   app-icon assets and update deprecated APIs before a release.

The scheme currently has no test targets. Compiler success alone does not verify
these workflows, old-system runtime compatibility, credential migration or signing.

## Preview

![Preview](./Resources/Preview.png)
![Preview+iOS](./Resources/Preview+iOS.jpeg)

## Features

- [x] **free and open source**
- [x] libssh2 capable host connections
- [x] Linux proc file system status information
- [x] authenticate with password, key, etc...
- [x] terminal with xterm support
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
