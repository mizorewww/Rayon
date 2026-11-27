# Rayon telemetry

Status: implemented (2026-11-27) in `Foundation/Telemetry` (client), `Server/Telemetry` (Worker + D1) and Settings › About › Diagnostics & Usage; the Worker is deployed at `https://telemetry.kfcv50.today` and Release builds send to it; §5 lists where the build differs from this plan. The user-facing setting is a 0–3 slider, default 2 (outside EEA/UK/CH). Every level must stay "Not Linked to You" and "Not Used to Track You" on the App Store label. Any change to what is sent must update this document, the privacy manifests and the App Store label together.

## Research and recommendation

Researched 2026-11-27. Sources were accessed on that date, and publication dates are given where the source shows one. Facts marked **(unverified)** could not be confirmed from a primary source.

## TL;DR

- **Crashes and hangs (level 1):** use Apple **MetricKit** (`MXDiagnosticPayload`). It needs no SDK, adds no binary weight and works in the sandbox. The payload is scrubbed on the device and sent to our own endpoint.
- **Usage (levels 2 and 3):** no vendor SDK. The app adds up counters on the device into **one aggregate report per device per day**, built only from enums and bucketed integers. The report carries **no install ID**, and the backend **never stores the IP address**. The backend is a small self-written ingest on **Cloudflare Worker + D1** behind a custom domain. Plan B, if mainland delivery turns out poor, is the same ~150-line ingest on a Hong Kong VPS with SQLite.
- **Vendor SDKs that were checked:**
  - **TelemetryDeck** does not meet the "impossible to link" requirement as shipped. Its SDK hashes `identifierForVendor` on iOS and a persisted UUID on macOS. It also sends screen resolution, time zone, first-session date and retention counters by default, and its own guide says to declare Device ID.
  - **Aptabase** is the best off-the-shelf fallback: an MIT SDK, a random session ID, the IP never stored, and an AGPL server that can be self-hosted.
  - **Sentry**, **PostHog** and **Crashlytics** are more than Rayon needs.
- **App Store label (all levels together, because the label is per app, not per level):**
  - **Diagnostics:** Crash Data, Performance Data, Other Diagnostic Data.
  - **Usage Data:** Product Interaction.
  - All declared as **Not Linked to You** and **Not Used to Track You**, purpose **Analytics**. No Identifiers and no Location.
  - **No level forces "Data Linked to You"** if the design below is followed. **ATT is not needed.**
- **Legal catch:**
  - App Store Guideline **5.1.1(ii)** says usage data needs consent "even if such data is considered to be anonymous".
  - EU ePrivacy Art. 5(3) (EDPB Guidelines 2/2023, v2, adopted 7 Oct 2024) covers an app making the device send data, whether or not it is personal data.
  - So a silent default of 2 is strictly defensible only outside the EEA/UK, and even there it relies on a visible notice.
  - Recommendation: one calm first-launch card everywhere. It acknowledges the default (2) outside the EEA/UK. In EEA/UK/CH storefronts nothing is preselected and nothing is sent until the user picks.

---

## 1. What Rayon has today

| Item | State |
|---|---|
| Licence | MIT (`LICENSE`, © 2022 Lakr Aream, © 2026 mizorewww and contributors). |
| Privacy policy | `Resources/AppStore/PrivacyPolicy`: a single line, "We do not record nor upload any user data." It must be rewritten before any telemetry ships. |
| Privacy manifest | Only iOS has one: `Application/mRayon/mRayon/PrivacyInfo.xcprivacy` (`NSPrivacyCollectedDataTypes` empty, UserDefaults CA92.1, FileTimestamp C617.1/3B52.1). **The macOS app has none**, so add one. Apple's required-reason enforcement targets iOS-family platforms, but the label must cover the Mac app too. |
| Telemetry code | None. No MetricKit, Sentry or analytics code anywhere. `UpdateManager` already calls the GitHub releases API, and the privacy policy should mention that. |
| Settings sync | `Foundation/RayonModule/Sources/RayonModule/Sync/AppSettingsSync.swift` syncs an explicit key allow-list through CKSyncEngine. |
| Existing "Privacy" UI | `RedactionMenu` in `Application/Rayon/Interface/Servers/ServersView.swift` hides addresses and names on screen. It is unrelated to telemetry, so name the new section "Diagnostics & Usage" to avoid confusion. |
| Settings UI | Mac: `Application/Rayon/Interface/Settings/SettingsView.swift`. iOS: `Application/mRayon/mRayon/Interface/Setting/SettingView.swift`. |

**FlowDown** (sister project, `../FlowDown`):
- Privacy statements: `Resources/Privacy/PrivacyStatements-2025.03.04.txt`, and `FlowDown/BundledResources/{en,zh-Hans}.lproj/PrivacyPolicy.md` (last updated Aug 12, 2026).
- Its stance is absolute: "No Data Collection", "No Telemetry", "No Crash Reports".
- The README brands it a Zero Data Retention app and notes that only the *website* uses anonymous analytics and Cloudflare.
- The manifest declares `NSPrivacyCollectedDataTypes` as empty and `NSPrivacyTracking` as false.
- The policy is bundled per locale and shown in-app by `PrivacyPolicyController.swift`. Rayon should copy that mechanism (en + zh-Hans + zh-Hant, matching Rayon's three READMEs).
- Note on brand risk: Rayon would diverge from the "nothing collected" promise of its sibling. Say so plainly in the README.

---

## 2. Backends compared

| | MetricKit | TelemetryDeck | Aptabase | PostHog | Sentry | Crashlytics | Self-built (Worker + D1) |
|---|---|---|---|---|---|---|---|
| What it covers | Crash, hang, CPU, disk-write and app-launch diagnostics, plus daily metrics | Product analytics | Product analytics (and basic error reports) | Analytics, replay, flags | Crash, performance | Crash | Whatever we define |
| Swift package | System framework | SPM, MIT, v2.14.2 (2026-08-01) | SPM, MIT, v0.4.0 (2026-10-23) | SPM, MIT, v4.1.1 (2026-11-26) | SPM, MIT, v9.36.0 (2026-11-26). CocoaPods stops after June 2026. | SPM (Firebase) | None needed (URLSession) |
| Binary size | 0 | Small (pure Swift) | Tiny (a dozen files) | About 1.5 MB (third-party figure) | Several MB; no official number found, so measure | Large (Firebase core) | 0 |
| Sandbox | Works | Needs outgoing-connections entitlement (Rayon has it) | Same; the README says so explicitly | Same | Works; the sandbox issue in its docs is only Xcode's user-script sandbox | Works | Works |
| Server licence | n/a | Closed SaaS | Server AGPL-3.0, SDK MIT. A separate service, so it does not touch Rayon's MIT code. | Server MIT core + EE | Self-hosted under FSL-1.1 (Apache-2.0 after 2 years) | Closed | Ours (MIT) |
| Hosting / residency | Apple → device → our server | EU-only (TelemetryDeck GmbH, Germany; docs say "all hosted within the EU") | Cloud EU (Germany) or US (Virginia); or self-host | Cloud US / EU (Frankfurt); self-host "hobby" Docker, limited support | US / EU cloud; self-host is heavy (many containers) | Google US | Cloudflare edge; D1 location hint (e.g. `apac` / `weur`) |
| IP handling | n/a | Says no IPs are kept in its database or logs. The web SDK uses only a leading IP prefix for country. | IP and User-Agent are processed in memory only. A daily SipHash of IP+UA with a salt rotated every 24 h and deleted within 48 h. Country/region is stored. | Per-project "discard client IP" setting (off by default for EU orgs). GeoIP still runs first. | Cocoa SDK doesn't send IP unless `sendDefaultPii`. The server can infer it unless "Prevent storing IP" is on. | Collects IP and Installation ID | We never read `CF-Connecting-IP`. Cloudflare still sees it as processor. |
| Identifier | None | **`identifierForVendor` (iOS) or a persisted UUID (macOS), SHA-256 hashed twice.** It can be overridden with `defaultUser`. | Random session ID, expires after inactivity. No device ID. | `distinct_id` (anonymous UUID, persisted) | Installation ID (persisted) | Installation UUID | None (per-report nonce) |
| Default extra fields | OS version, device type, binary UUIDs, stack frames, exception type/signal, termination reason | **Model, OS, architecture, screen width/height/scale, time zone, locale, region, colour scheme, first-session date, retention counters, …** (read from `Signal.swift` in the SDK) | OS name/version, locale, app version/build, device model, debug flag, SDK version | Many: device, screen, locale, network | Device, OS, memory, app context, breadcrumbs | Device, OS | Only our enums |
| Apple label, vendor's own advice | Crash, Performance (Not Linked) | **Device ID + Product Interaction** (Not Linked) | Product Interaction + **Coarse Location** (+ Crash Data if enabled). No identifiers. | Usually Device ID + Product Interaction + more | Crash + Performance + Device ID | Crash + Device ID | Crash, Performance, Other Diagnostic, Product Interaction. No ID, no location. |
| Mainland China without VPN | Upload goes to our endpoint, so same as ours | **(unverified)** EU host, no China PoP. Expect it mostly works but slowly. | **(unverified)** same | **(unverified)** same | Sentry's help centre: not built for China, "connectivity may be disrupted", no PIPL compliance plans | Google domains are blocked: **no** | Cloudflare outside its China Network (JD Cloud, Enterprise only) is reachable but variable on a custom domain. `*.workers.dev` is widely reported as DNS-polluted **(unverified)**. |
| Price (2026) | Free | Free tier 50k events/mo for new accounts since 1 Jul 2026; paid tiers 1.5M / 2.5M / 5M | Free 20k/mo; $10 for 200k; $20 for 1M; $40 for 2M. Self-host is free. | 1M events/mo free | Developer: free, 1 user, 5k errors. Team about $26/mo. | Free | Workers free: 100k req/day; paid $5/mo. D1 free: 100k row writes/day, 5 GB. |
| Fits "impossible to link"? | Yes, after stripping exception messages | **No, as shipped** (persistent ID + fingerprint-grade defaults) | Close. Session-scoped ID, no IP stored. The server derives a daily pseudonymous hash, which is acceptable. Self-host to also drop geo. | Only with heavy configuration | No for analytics. Possible for crashes with scrubbing, but overkill. | No | Yes, by construction |

**Verdict.**
- **Level 1:** MetricKit, with no third party.
- **Levels 2 and 3:** the self-built aggregate report. If the maintainer prefers not to own the ingest, Aptabase is the off-the-shelf choice: self-hosted on a Hong Kong, Tokyo or Singapore VPS so that geo stays off, the IP is never logged and mainland latency stays reasonable.
- Avoid TelemetryDeck despite its popularity (Secure ShellFish uses it). Its default payload and persistent hashed ID conflict with requirement (2), and its own guide tells you to declare Device ID.

**MetricKit details:**
- Requires macOS 12 / iOS 14; diagnostics on iOS 14+. With Rayon's iOS 18 / macOS 15 minimum, there are no availability branches.
- Since iOS 15 / macOS 12, diagnostics are delivered right away (on the next launch) rather than in the daily batch. Apple's own documentation is vague on this, and Sentry's docs state it.
- Known gaps:
  - On macOS a hang diagnostic arrives only if the app never recovers (Apple forums).
  - Some releases (iOS 17.2–17.5) dropped crash and hang reports (Apple forums).
  - Delivery is best-effort, so treat it as a sample, not a census.
- Payloads contain symbol-less call-stack trees (binary UUID + offset). Symbolicate offline against the archived dSYMs, including libghostty's if it ships them.
- Scrub before upload. `MXCrashDiagnostic.exceptionReason.composedMessage` / `arguments` (iOS 17 / macOS 14+) can carry user strings such as a host in an `NSException` reason.

---

## 3. Legal and policy

### Apple (App Review Guidelines 5.1, nutrition label, privacy manifest)

- **5.1.1(i):**
  - A privacy policy link is needed in App Store Connect and "within the app in an easily accessible manner".
  - It must say what is collected, how and why.
  - It must name third parties (Cloudflare as processor, or Aptabase / Hetzner if used).
- **5.1.1(ii):**
  - Verbatim: "Apps that collect user or usage data must secure user consent for the collection, even if such data is considered to be anonymous at the time of or immediately following collection."
  - It also requires "an easily accessible and understandable way to withdraw consent".
  - Paid functionality must not depend on it.
  - Strictly read, a silent default of 2 does not satisfy this. In practice Apple accepts default-on anonymous analytics with a notice and an opt-out:
    - Panic's Prompt collects anonymous usage "by default" and lets users opt out (help page, updated 24 Oct 2023).
    - Secure ShellFish uses TelemetryDeck.
  - The first-launch card below is the cheap way to meet the letter of the rule.
- **5.1.1(iii), data minimisation:** the allow-list below is the answer to this rule.
- **5.1.2(i):** no third-party sharing beyond the processor, and no tracking, so ATT is not needed. Apple's definition of tracking is linking with third-party data for advertising or ad measurement, or sharing with data brokers.
- **"Not linked to you":**
  - Apple requires stripping direct identifiers before collection and manipulating the data "to break the linkage and prevent re-linkage". After collection you must not try to re-link it or join it with datasets that allow it.
  - The design here meets this: no ID, no IP stored, coarse buckets, day-level time.
- **"Product Improvement Program" exemption (no declaration at all):**
  - It requires an **explicit opt-in with two clear options**, so it is unavailable when the default is 2.
  - It *would* apply to EEA users who opt in, but the label is global, so declare anyway.
- **The label is per app, not per level.** Declare the union of everything level 3 can send. Default-on also means the "optional disclosure" exemption does not apply.

**Label to enter in App Store Connect (both apps):**

| Category | Data type | Level that sends it | Purpose | Linked | Tracking |
|---|---|---|---|---|---|
| Diagnostics | Crash Data | 1+ | Analytics (+ App Functionality if you also use it to ship fixes) | No | No |
| Diagnostics | Performance Data | 1+ (hang), 3 (metrics) | Analytics | No | No |
| Diagnostics | Other Diagnostic Data | 3 (enum-only connection/protocol diagnostics) | Analytics | No | No |
| Usage Data | Product Interaction | 2+ | Analytics | No | No |
| Identifiers | (none) | – | – | – | – |
| Location | (none; do not derive country from IP. If Aptabase cloud is used, add Coarse Location.) | – | – | – | – |

**`PrivacyInfo.xcprivacy` (add to both the iOS and Mac targets):**
- `NSPrivacyCollectedDataTypes` gets four dicts with these types:
  - `NSPrivacyCollectedDataTypeCrashData`
  - `NSPrivacyCollectedDataTypePerformanceData`
  - `NSPrivacyCollectedDataTypeOtherDiagnosticData`
  - `NSPrivacyCollectedDataTypeProductInteraction`
- Each dict sets `NSPrivacyCollectedDataTypeLinked = false`, `NSPrivacyCollectedDataTypeTracking = false` and `NSPrivacyCollectedDataTypePurposes = [NSPrivacyCollectedDataTypePurposeAnalytics]`.
- `NSPrivacyTracking` stays false, and `NSPrivacyTrackingDomains` stays empty.
- Required-reason APIs:
  - Keep UserDefaults `CA92.1`.
  - Do **not** compute "days since install" from file timestamps or `systemUptime`, so no new reasons are needed.
  - If durations are measured with `ProcessInfo.systemUptime` or `mach_absolute_time`, declare `NSPrivacyAccessedAPICategorySystemBootTime` `35F9.1`. Prefer `ContinuousClock` deltas inside one session, which have the same issue, so declare 35F9.1 if any monotonic clock is read for timing.

**Does any level force "Data Linked to You"?**
- Not with this design.
- It would be forced by any of these:
  - a persistent install ID that survives reinstall or is synced through iCloud;
  - attaching an email, account, iCloud record ID or Rayon account (the Mac settings show a signed-in account; never put it in a report);
  - free-text fields;
  - storing IPs.
- A user-initiated "Send diagnostics to support" with an email address would be linked, unless it is truly per-submission and user-initiated, in which case it meets the optional-disclosure criteria. Keep that path separate from the slider.

### EU (GDPR + ePrivacy)

- **ePrivacy Art. 5(3):**
  - Consent is needed to store or access information on the terminal unless it is strictly necessary for a service the user asked for.
  - EDPB Guidelines 2/2023, v2.0 (adopted 7 Oct 2024), read "gaining access" broadly, so it includes software that makes the device send data.
  - This applies **even if the data is not personal**. Germany's TDDDG §25 is the same.
  - Crash and usage analytics are generally *not* "strictly necessary".
- **The French exemption:** CNIL's audience-measurement exemption (Sheet 16) allows consent-free, first-party, anonymous statistics with an opt-out, no cross-site/app use and limited retention. It is a French reading; other DPAs are stricter.
- **GDPR:** truly anonymous data falls outside it (Recital 26). A daily aggregate with no ID, no IP and k-bucketed values is a strong anonymity case, and Art. 11 means we need not re-identify anyone to honour access or deletion requests.
- **Practical conclusion:** in the **EEA, UK and CH**, default = **not chosen** (nothing sent). The first-launch card offers two equal buttons, and a pre-ticked level 2 is not valid consent (CJEU *Planet49*, 2019).
  - **Detect the region with StoreKit `Storefront.current?.countryCode`** for App Store builds, and `Locale.current.region` for direct downloads.
  - Elsewhere, default = 2 with the notice.

### China (PIPL)

- **Anonymised information is not personal information:** Art. 4 excludes it, and Art. 73 defines it as impossible to identify and impossible to restore. No technical standard defines this, so it is safer to keep the design obviously aggregate.
- **If it were personal information:**
  - Consent would need to be informed, voluntary and explicit (Art. 14).
  - Cross-border transfer would need **separate consent** plus a transfer mechanism (Arts. 38–39).
  - Sentry's help centre states it has no plans to comply with China's rules.
  - Shipping per-device identifiers to an overseas vendor is exactly what puts an app in that box.
- Chinese app-compliance practice (MIIT enforcement) expects the privacy policy to be shown at first launch, before any SDK collects anything, and no collection before the user agrees.
  - The same first-launch card covers this.
  - For China-storefront users, show the policy link prominently and send nothing until the card is dismissed.
- Endpoint reachability is a product risk, not a legal one. Measure delivery from mainland probes before launch: enable level 2 in a TestFlight build and compare report counts per storefront against App Store Connect active devices.

### What comparable apps do

| App | Telemetry | Default | Source |
|---|---|---|---|
| Panic Prompt | Anonymous usage via App Center; excludes terminal I/O, hosts, usernames, passwords, keys and IP | **On**, opt-out in About → Privacy | help.panic.com/prompt/prompt-privacy (updated 2023-10-24). App Center itself was retired in 2025, so Panic presumably migrated. |
| Secure ShellFish | TelemetryDeck: terminal start success/failure, feature use; "no server details or error details" | Not stated | secureshellfish.app/privacy.html; telemetrydeck.com/apps/secure-shellfish |
| Tabby | Mixpanel with a persistent UUID in localStorage; `freshInstall` and `launch` events | **On** (`enableAnalytics: true` in `configDefaults.yaml`; pre-ticked toggle on the welcome tab; off on web) | github.com/Eugeny/tabby `tabby-core/src/services/homeBase.service.ts` |
| Warp | Telemetry + crash reports, two toggles | On. On the free plan telemetry is required for AI features. | docs.warp.dev privacy page |
| Termius | Google Analytics, Firebase, Mixpanel, Hotjar, ChartMogul; device IDs | On; few opt-outs | termius.com/privacy-policy (footer "Last updated: January 30, 2025") |
| Ghostty | Sentry-format crash envelopes **stored locally only**; the user uploads them by hand | Nothing sent | ghostty source `src/crash/sentry.zig` |
| iTerm2 | No analytics SDK found; Sparkle update checks; its test VM script sets `SUSendProfileInfo false` | Update check on | gnachman/iTerm2 repo |
| FlowDown | Nothing | Nothing | in-repo policy |

The norm among *privacy-respecting* native SSH clients (Prompt, ShellFish) is default-on anonymous usage with an opt-out and explicit exclusions of hosts, users, keys and content. Rayon's design is stricter than both.

---

## 4. Recommendation

### 4.1 Levels (refined)

| Level | Name in UI | Sends | Default |
|---|---|---|---|
| 0 | Off | Nothing. MetricKit subscriber removed. No network call to the telemetry host at all. | – |
| 1 | Crash Reports | Scrubbed MetricKit crash and hang diagnostics, plus app version and OS bucket | – |
| 2 | Crash Reports and Usage | Level 1 plus **one daily aggregate report**: feature counters and environment buckets | **Yes** (non-EEA) |
| 3 | Detailed Diagnostics | Level 2 plus performance metrics (`MXMetricPayload` histograms, bucketed connect latency) and enum-only protocol diagnostics; **10 % sampled per day** | – |

### 4.2 Field allow-list

The report is a Swift `Codable` struct whose fields are **only enums, `Bool` and bucketed `Int`, never `String`**. Enum raw values are fixed constants, which makes the allow-list a compile-time property. A unit test snapshots the JSON schema, so adding a field becomes a reviewed change.

**Envelope (every report):**
- `schema`: Int.
- `nonce`: a random UUID per report, used only for server-side dedup of retries, then dropped.
- `level`: 1, 2 or 3.
- `appVersion`: for example "5.2.0", from our own Info.plist.
- `channel`: appStore / direct / testFlight / debug. Debug is never sent.
- `platform`: macOS / iOS / iPadOS.
- `osVersion`: **major.minor only** (15.4, not 15.4.1).
- `deviceClass`: mac-appleSilicon / mac-intel / iPhone / iPad. No model identifier.
- `language`: one of the app's localisations (en, zh-Hans, zh-Hant, other).
- `regionGroup`: EEA / CN / other, derived from the storefront. It is coarse, so no Location label is needed. Consider omitting it entirely.
- **No timestamp.** The server stamps the UTC date (day) at ingest.

**Level 1, crash/hang item:**
- `kind`: crash / hang / cpuException / diskWriteException.
- `appVersion`, `osVersion`.
- `exceptionType`, `signal`, `exceptionCode`: integers.
- `terminationReason`: mapped to an enum. **Do not** send the raw string.
- `objcExceptionName` / `className`: only when it matches an allow-list of system exception names.
- `callStackTree`: binary name, **binary UUID**, offset address. Drop frames whose binary is not ours or a system framework.
- `hangDurationBucket`.
- **Strip** `composedMessage`, `arguments`, `virtualMemoryRegionInfo` and every free-form string.

**Level 2, daily counters:** each is bucketed as 0 / 1 / 2–5 / 6–20 / 21–100 / 100+.
- `terminalSessionsOpened`, `sftpBrowsed`, `fileTransfers`, `editorOpened`
- `portForwardsStarted` by type (local / remote / dynamic)
- `monitorOpened`, `vncSessions`, `uuRemoteSessions`, `snippetsRun`
- `connectionOutcome`: a count per enum value: success / authFailed / timeout / refused / hostKeyMismatch / dnsFailed / other
- `authMethodUsed`: password / publicKey / agent / keyboardInteractive (Bool each)
- `keyTypes`: ed25519 / ecdsa / rsa (Bool each)
- `savedHostsBucket`, `identitiesBucket`
- `iCloudSyncEnabled`, `customTheme`, `redactionMode` (enum)
- `activeDaysLast28Bucket`: computed on the device from a local set of day numbers that never leaves the device. It gives retention without any ID.

**Level 3, additionally:**
- `MXMetricPayload` histograms (launch time, hang rate, peak memory, CPU time, disk writes), re-bucketed
- `connectLatencyBucket` histogram
- Negotiated SSH algorithms, as enums from a fixed list: kex / cipher / MAC / host-key algorithm
- `remoteOSFamily`: linux / darwin / bsd / other, from the monitor's `uname -s` mapped to an enum
- Remote-desktop encoding and codec enums
- Terminal frame-time histogram bucket

**Forbidden, at every level.** A test greps the encoded JSON of a fuzzed report for these patterns:
- hostnames, IPs (v4 or v6), ports, usernames
- key fingerprints, comments or public keys; passwords and passphrases
- commands, snippets, terminal input/output, clipboard
- paths, file names, file sizes (exact), remote `uname` / banner / SSH version strings
- `localizedDescription` or any error message string
- env vars, iCloud / CloudKit record IDs, Rayon account names, IDFV, IDFA, serial numbers
- exact timestamps, time zone, screen size, network type or SSID, locale region beyond regionGroup

### 4.3 Identity, k-anonymity, server side

- **No install ID.** The only ID is the per-report `nonce`.
- Each device sends at most one level 2/3 report per UTC day, so the report count approximates daily active devices.
- Use no persistent session ID. If one is ever needed, make it an in-memory UUID per launch.
- **Server:**
  - Never read or log `CF-Connecting-IP` or `User-Agent`. Turn off Workers Logs and Logpush for this route, and do not enable Cloudflare analytics that persist IPs.
  - Insert straight into **aggregate tables** (date × appVersion × osVersion × counter bucket → count) and drop the raw report.
  - Keep raw crash items 90 days for symbolication, then delete.
- **k-anonymity:** dashboards and exports suppress any cell with fewer than 10 devices. Fold rare `osVersion` and `appVersion` values into "other" on the server.

### 4.4 Sampling, batching, offline queue

- **Level 1:** 100 %. Crashes are rare, and MetricKit already samples.
- **Level 2:** 100 % (one request per device per day).
- **Level 3:** extras are included on 10 % of days, chosen by a per-day coin flip on the device.
- **Queue:**
  - JSON files in `Application Support/Telemetry/pending/`, at most 14 files; older ones are dropped.
  - Send on launch, on foreground and at day rollover.
  - Use `URLSession(configuration: .ephemeral)`: no cookies, no cache, `waitsForConnectivity`, exponential backoff.
  - Up to 10 reports go in one POST, so the offline backlog is one request.
  - Send nothing in debug builds or under `RAYON_PREVIEW_*`.

### 4.5 Level changes

- The change applies **immediately**:
  - **Lowering:** delete pending files and local counters above the new level right away. Going to 0 also calls `MXMetricManager.shared.remove(subscriber)` and deletes the queue directory. It does not delete the local active-days set, which never leaves the device; offer that in a "Reset" button.
  - **Raising:** collect from now on only. Nothing is backfilled.
- Server-side deletion is not possible by design: there is no identifier. The policy says so, citing GDPR Art. 11.
- **iCloud:** do **not** add the level to `AppSettingsSync.keys`. It stays device-local:
  - Consent is per device and per storefront (EEA vs. elsewhere).
  - Syncing could silently turn on collection on a device the user never saw the notice on.
  - The setting text says "on this device". If cross-device lowering is wanted later, sync only a "minimum level" that can lower but never raise. This is not needed now.

### 4.6 UI (calm, no nags, no dark patterns)

- **Mac:** add a **"Diagnostics & Usage"** section in `SettingsView.swift`, next to About/License. **iOS:** add a `Section` in `SettingView.swift`.
- **Slider:** `Slider(value: $level, in: 0...3, step: 1)`, which shows tick marks, with `minimumValueLabel` "Off" and `maximumValueLabel` "Detailed". `accessibilityValue` is set to the level name.
- **Description text** under the slider, one line each:
  - 0: "Nothing is sent."
  - 1: "Crash and hang reports, without your hosts, names or terminal content."
  - 2: "Also a daily count of which features are used. No identifier, no IP address kept."
  - 3: "Also performance timings and protocol details, on some days."
- A fixed footnote: "Never sent: server addresses, usernames, keys, commands, files or terminal content." Then a "Privacy Policy" link.
- **"View What's Sent…"** opens a sheet with:
  - the pending reports and the last sent report, as pretty JSON in monospace, selectable;
  - a `ShareLink`;
  - "Delete Pending Reports".
- **First-launch card:** one card, inline in the first window, not a modal sheet that blocks work. It is shown once and never re-shown, with no badge and no reminder.
  - **Non-EEA:** "Rayon sends anonymous crash reports and feature counts to help fix bugs. It never sends your servers, usernames or terminal content." Buttons: [Settings…] [OK]. The level stays 2.
  - **EEA/UK/CH:** the same text, then two equal-weight buttons, [Share Anonymous Data] (→ 2) and [Don't Share] (→ 0). Nothing is sent before a choice. Dismissing the card counts as "Don't Share".
  - **China storefront:** the non-EEA variant, with the privacy-policy link in the card body.
- Tasteful also means the level never changes features, never appears in onboarding twice, and is never re-asked after an update unless the data definition changes, which would be a schema bump.

### 4.7 Privacy policy contents (new; en / zh-Hans / zh-Hant, bundled as FlowDown does)

1. What each level sends: the allow-list in plain words.
2. What is never sent: the forbidden list.
3. No identifiers, no IP storage, day-level dates, aggregation, k ≥ 10, 90-day crash retention.
4. Processor: Cloudflare, Inc., with the region. Name Aptabase or the VPS host if used. Add the GitHub API for update checks.
5. How to change or withdraw: Settings path, immediate effect, local deletion; why server-side deletion is impossible.
6. Legal basis per region: EEA consent; elsewhere legitimate interest / anonymous data; PIPL.
7. Contact and date.

Also update the README "Privacy" wording and the App Store label at the same time as the release that ships it.

### 4.8 Cost

Assume 30k daily active devices, 70 % at level ≥ 2. That is about 21k requests and writes a day, which fits the Workers free tier (100k requests/day) and D1 free (100k row writes/day). Pre-aggregation keeps the writes low.
- Above that: Workers Paid at $5/mo.
- Plan B, a Hong Kong VPS: about $5–10/mo.
- Aptabase cloud at the same volume: about 630k events/mo, so the $20 tier. Self-hosted Aptabase needs a ClickHouse-capable VPS (≥ 4 GB RAM, about $10–20/mo).
- Engineering: about 1–2 days for the client (report struct, MetricKit subscriber, queue, UI) and half a day for the Worker.

### 4.9 Risks

- **Guideline 5.1.1(ii) literalism:** a reviewer could reject a silent default-on. The first-launch card mitigates this.
- **EEA default-on** would breach ePrivacy 5(3); hence the storefront-based split. Storefront detection is wrong for direct-download users who travel, so fall back to the stricter variant when unsure.
- **Mainland reachability** of a Cloudflare custom domain is not guaranteed, and data from China users may be under-counted. Measure it, and keep the Hong Kong VPS as plan B. Do not use `workers.dev`.
- **MetricKit gaps:** macOS hang delivery, OS-version bugs, and no data for some crashes (for example watchdog kills). Accept the loss, or add a local crash-marker heuristic later.
- **Leaking through MetricKit strings** (exception reasons, termination reasons): mitigate with allow-list mapping and a test using crafted payloads (Xcode's "Simulate MetricKit Payloads").
- **Brand contrast with FlowDown's "nothing collected"**, and community pushback (open-source users are sensitive; see Warp and Tabby discussions). Publish the schema in the repo and point to "View What's Sent".
- **Scope creep:** every new counter is a schema change that needs review against this allow-list and a label check.

---

## 5. As built

### 5.1 Where it lives

- `Foundation/Telemetry`: the report (`TelemetryReport*.swift`, enums, `Bool` and bucketed `Int` only), the MetricKit subscriber and scrubber, the on-device counters (`TelemetryCollector`), the queue in `Application Support/<bundle id>/Telemetry/pending` and the sender. `Telemetry.shared` holds the level. The app keeps it as `AppSettings.telemetryLevel` (with `telemetryNoticeShown`), scope `.deviceLocal`, so neither iCloud nor the preferences backup carries it. The tests pin the JSON in `Tests/TelemetryTests/Fixtures/report-sample.json` and every enum case in `report-enums.json`.
- `RayonModule` re-exports Telemetry and records events at `RDMachine.connectSSH` (outcome, sign-in method, latency), `TerminalManager`, `FileTransferManager`, `FileTransferContext.upload/download`, `EditorWorkspace.open`, `PortForwardBackend`, `RemoteDesktopManager` and `BatchSnippetExecContext`. `MachineStatusView` records monitor opens and the remote OS family from `uname -s`.
- The app: `Interface/Settings/DiagnosticsSettings.swift` (the slider, the notice card on Home, "View What's Sent…", the privacy policy sheet) and `Application/TelemetrySnapshot+Rayon.swift`. The privacy policy is bundled from `Resources/Privacy/PrivacyPolicy-{en,zh-Hans,zh-Hant}.md`. `Resources/AppStore/PrivacyPolicy` is a copy of the English text for App Store Connect; keep the two identical.
- `Server/Telemetry`: the Worker, deployed with `cf` as `rayon-telemetry` on the custom domain `telemetry.kfcv50.today` with D1 database `rayon-telemetry` (APAC). Its README has the deploy commands. `TelemetryEndpoint.url` points the app at it.

### 5.2 Differences from §4

- **Level 3 extras.** Built: MetricKit daily metrics (launch, hang time, peak memory, CPU time, disk writes) re-bucketed, the sign-in latency histogram and the remote OS family. Not built, because nothing in Rayon exposes the value without new plumbing: the negotiated SSH algorithms (NIOSSH does not report them), the remote-desktop encodings and codecs, and the terminal frame time. Each is a schema change when added.
- **Connection outcome.** RayonSSH folds NIO errors into its message, so `refused`, `dnsFailed` and `timeout` are recognised from the phrases `SSHTransport.describe` writes (`TelemetryReport.ConnectionOutcome(reason:)`). A changed phrase falls back to `other`.
- **Key types** are those among the saved identities, read from the public key or the PEM header, not the key used that day.
- **Call stacks.** A frame keeps its binary UUID and offset only when its UUID is the app's executable, or an image loaded from `/System/` or `/usr/lib/`, or its binary name is the app's. Other frames keep their place in the tree as `origin: other`. Binary names and absolute addresses are never sent. A crash keeps only its crashed thread, and a diagnostic at most 512 frames.
- **Days** are the device's local calendar days; the server still stamps the UTC day of arrival. The finished day's report is queued at the first launch, foreground or `NSCalendarDayChanged` of a later day.
- **China storefront.** Nothing is collected until the notice is dismissed, as §3 asks. The card also links the privacy policy there.
- **Region unknown** counts as strict: nothing is sent until a choice.
- **The privacy policy files are not in `.lproj` folders.** Those would mark the app as localized into Chinese and switch the system-provided menus to Chinese around English rows. The sheet picks the file with `Bundle.preferredLocalizations(from:forPreferences:)`.
- **Server rows.** `os_version` is stored as `<platform> <major.minor>` (`macOS 15.4`), because the bare number is the same for macOS and iOS 26. Zero counts and `false` flags are not written, since they follow from the `reports` totals; this keeps D1 writes per report near ten. Reports go in at `POST /v1/reports` as `{"reports": [...]}`, one to ten per request. A 400, 413 or 422 makes the app drop the batch, and anything else keeps it queued with backoff from 1 minute up to 6 hours.
- **The sender** sets `User-Agent: Rayon`, so even Cloudflare's edge does not see the exact OS build.

### 5.3 App Store Connect privacy label

Enter this once for the app, on both the iOS and macOS records, before the release that ships the real endpoint.

1. **Do you or your third-party partners collect data from this app?** Yes.
2. **Data types:** select exactly these four. Select nothing under Contact Info, Health & Fitness, Financial Info, Location, Sensitive Info, Contacts, User Content, Browsing History, Search History, Identifiers, Purchases or Other Data.
   - Diagnostics › **Crash Data**
   - Diagnostics › **Performance Data**
   - Diagnostics › **Other Diagnostic Data**
   - Usage Data › **Product Interaction**
3. For **each** of the four, answer:
   - Purposes: **Analytics** only. Not App Functionality, Product Personalization, Developer's Advertising or Marketing, Third-Party Advertising or Other Purposes.
   - **Is this data linked to the user's identity?** No.
   - **Is this data used for tracking purposes?** No.
4. The resulting label reads "Data Not Linked to You: Diagnostics, Usage Data" and has no "Data Used to Track You" section.
5. **Privacy Policy URL:** the published copy of `Resources/AppStore/PrivacyPolicy`, for example `https://github.com/mizorewww/Rayon/blob/main/Resources/AppStore/PrivacyPolicy`.

`Application/Rayon/Resources/PrivacyInfo.xcprivacy`, shared by the Mac and iOS builds of the one target, declares the same four types (not linked, not tracking, Analytics). It also adds `NSPrivacyAccessedAPICategorySystemBootTime` `35F9.1` for the `ContinuousClock` that times sign-ins.

---

## Sources

- TelemetryDeck pricing update (2026-07-01, updated 2026-10-12): https://telemetrydeck.com/blog/pricing-update-2026/
- TelemetryDeck hosting: https://docs.telemetrydeck.com/articles/hosting-solutions/
- TelemetryDeck Apple label guide: https://docs.telemetrydeck.com/articles/apple-app-privacy/
- TelemetryDeck double hashing: https://telemetrydeck.com/feature/double-hashing/
- TelemetryDeck privacy FAQ: https://telemetrydeck.com/docs/guides/privacy-faq/
- TelemetryDeck privacy policy: https://telemetrydeck.com/privacy
- TelemetryDeck SDK source, `SignalManager.swift` (`identifierForVendor` / persisted UUID) and `Signal.swift` (default payload): https://github.com/TelemetryDeck/SwiftSDK (release 2.14.2, 2026-08-01)
- Aptabase pricing: https://aptabase.com/pricing.md
- Aptabase privacy policy: https://aptabase.com/legal/privacy
- Aptabase Apple label guide: https://aptabase.com/docs/apple-app-privacy
- Aptabase server (AGPL-3.0): https://github.com/aptabase/aptabase
- Aptabase Swift SDK (MIT, 0.4.0, 2026-10-23): https://github.com/aptabase/aptabase-swift
- PostHog self-host: https://posthog.com/docs/self-host
- PostHog data storage and IP discard: https://posthog.com/docs/privacy/data-storage
- PostHog README (free tier): https://github.com/PostHog/posthog
- Sentry Apple data collected: https://docs.sentry.io/platforms/apple/data-management/data-collected
- Sentry troubleshooting: https://docs.sentry.io/platforms/apple/guides/macos/troubleshooting/
- Sentry MetricKit integration: https://docs.sentry.io/platforms/apple/configuration/metric-kit
- Sentry China coverage: https://sentry.zendesk.com/hc/en-us/articles/23846111639323
- Sentry China data-transfer compliance: https://sentry.zendesk.com/hc/en-us/articles/25997440902171
- Sentry pricing summary (2026): https://www.activepieces.com/blog/sentry-pricing-2026-developer-team-business-plans
- Sentry self-hosted licence (FSL-1.1): https://github.com/getsentry/self-hosted
- Apple MetricKit, `MXDiagnosticPayload`: https://developer.apple.com/documentation/metrickit/mxdiagnosticpayload
- Apple MetricKit, `MXCrashDiagnostic`: https://developer.apple.com/documentation/metrickit/mxcrashdiagnostic
- Apple forum, macOS hangs: https://developer.apple.com/forums/thread/729815
- Apple forum, iOS 17.2–17.5 gap: https://developer.apple.com/forums/thread/806457
- Apple App Privacy Details: https://developer.apple.com/app-store/app-privacy-details/
- Apple App Review Guidelines, 5.1: https://developer.apple.com/app-store/review/guidelines/
- Cloudflare D1 pricing: https://developers.cloudflare.com/d1/platform/pricing/
- Cloudflare China Network: https://www.cloudflare.com/network/china/
- EDPB Guidelines 2/2023, v2 (2024-10-07): https://edpb.europa.eu/system/files/2024-10/edpb_guidelines_202302_technical_scope_art_53_eprivacydirective_v2_en_0.pdf
- CNIL Sheet 16, analytics: https://www.cnil.fr/en/sheet-ndeg16-use-analytics-your-websites-and-applications
- CNIL mobile app recommendations (2025): https://cnil.fr/en/node/166141
- PIPL translation, DigiChina: https://digichina.stanford.edu/work/translation-personal-information-protection-law-of-the-peoples-republic-of-china-effective-nov-1-2021/
- Panic Prompt privacy (2023-10-24): https://help.panic.com/prompt/prompt-privacy/
- Secure ShellFish privacy: https://secureshellfish.app/privacy.html
- Secure ShellFish on TelemetryDeck: https://telemetrydeck.com/apps/secure-shellfish
- Warp privacy: https://docs.warp.dev/support-and-community/privacy-and-security/privacy/
- Termius privacy policy: https://termius.com/privacy-policy
- Tabby source: https://github.com/Eugeny/tabby (`tabby-core/src/configDefaults.yaml`, `services/homeBase.service.ts`)
- Ghostty crash reporter: https://github.com/ghostty-org/ghostty (`src/crash/sentry.zig`)
