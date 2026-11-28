# Rayon Privacy Policy

_Last updated: November 28, 2026_

Rayon is an SSH and server client. Your servers, identities, keys, passwords, snippets, port forwards, files and terminal sessions stay on your devices, and in your own iCloud account if you turn on iCloud Sync. Nobody else can read them, including the Rayon developers.

The only data Rayon sends to its developers is anonymous diagnostics and usage counts. You choose how much under Settings › About › Diagnostics & Usage, and you can turn it off at any time.

## 1. What each level sends

- **Off (0):** nothing. Rayon makes no connection to its telemetry server.
- **Crash Reports (1):** crash and hang reports from Apple's MetricKit, stripped on your device of every message and name. What is left is the kind of problem, numeric exception and signal codes, a category for the termination reason, a system exception name from a fixed list, a rough hang duration, and call stacks as binary IDs and offsets within Rayon and the system.
- **Crash Reports and Usage (2):** level 1, plus one report per day with counts of feature use, each rounded into a range (0, 1, 2–5, 6–20, 21–100, more than 100). The features counted are terminal sessions opened, file browsers opened, file transfers, the editor, monitors, VNC and UU Remote sessions, snippets run and port forwards by type. The report also counts connection outcomes (such as success, sign-in refused, timeout, refused, host key not trusted, host not found) and says which sign-in methods were used that day (password, key, agent). It also carries the key types among your identities (Ed25519, ECDSA, RSA), ranges for the number of saved servers and identities, whether iCloud Sync, a custom terminal theme and hiding of addresses are on, and a range for the number of days Rayon was used in the last 28.
- **Detailed Diagnostics (3):** level 2, plus on about one day in ten: ranges for sign-in time, the operating-system family of the servers you monitor (Linux, macOS, BSD, other), and Apple's daily performance figures (launch time, hang time, peak memory, CPU time, disk writes), each rounded into a range.

Every report also carries the Rayon version, the operating system's major and minor version, the platform (macOS, iOS or iPadOS), the device class (Mac with Apple silicon, Intel Mac, iPhone or iPad), the app's language (English, Simplified Chinese, Traditional Chinese, Japanese, French, Spanish or other), how Rayon was installed (App Store, TestFlight or direct download) and a coarse region group (EEA/UK/Switzerland, mainland China or other) taken from your App Store country.

You can see the exact reports in Settings › About › Diagnostics & Usage › View What's Sent…

## 2. What is never sent

At any level, Rayon never sends: server names, addresses, ports or user names; passwords, passphrases, keys, key fingerprints or key comments; commands, snippets, terminal input or output, or the clipboard; file names, paths or sizes; remote banners or version strings; error messages; environment variables; iCloud or account identifiers; device identifiers (such as IDFV, IDFA or serial numbers); exact times, time zone, screen size, network type or Wi-Fi name; or your location.

## 3. How the data is kept

- Reports carry **no identifier** of you, your device or your installation. Each report has a random number used only to drop a duplicate if it is sent twice; it is deleted within three days.
- The server **never reads or stores your IP address** or browser/user-agent string, and keeps no request logs.
- Dates are kept to the day. Each report is added into daily totals as soon as it arrives and is then discarded. Crash and hang items are kept for **90 days** for diagnosis, then deleted.
- Totals of fewer than **10** reports are never shown or exported.
- Because nothing identifies you, a report cannot be linked to you afterwards. The data is not used to track you, is not sold, and is not shared except with the processor below.

## 4. Who processes it

- **Cloudflare, Inc.** runs the telemetry server (a Cloudflare Worker with its D1 database, located in the Asia-Pacific region) as Rayon's processor. Cloudflare's network necessarily sees the connection, including its IP address, while delivering it; Rayon's server does not read it.
- **GitHub, Inc.** answers "Check for Updates…" in the Mac app, which asks GitHub's public API for the latest release only when you choose that command. GitHub sees that request under its own privacy statement.
- **Apple** provides MetricKit, iCloud Sync (your data in your own iCloud account) and the App Store, under Apple's privacy policy.
- Services you connect Rayon to yourself, such as your servers, Cloudflare Access or UU Remote, receive what you send them under their own policies.

## 5. Changing or withdrawing your choice

Open Settings › About › Diagnostics & Usage and move the slider. The change takes effect at once. Lowering the level deletes, on this device, the waiting reports and counts the new level would not send; Off also stops MetricKit delivery to Rayon and deletes the report queue. "Delete Pending Reports" and "Reset Activity History" in View What's Sent… clear the rest. The setting is kept on each device and is never synced.

Reports already sent cannot be deleted on request, because nothing in them identifies whose they are (GDPR Article 11).

## 6. Legal basis

- **EEA, United Kingdom and Switzerland:** your consent. Nothing is sent until you choose "Share Anonymous Data", and you can withdraw at any time.
- **Mainland China:** nothing is sent until you have seen the notice and this policy. The data is anonymised information under the Personal Information Protection Law (Article 4, Article 73).
- **Elsewhere:** our legitimate interest in fixing bugs and improving Rayon, with data that is anonymous by design. Level 2 is the default and the first-launch notice tells you so.

Rayon is not directed at children and does not knowingly collect data from them.

## 7. Contact and changes

Questions and requests: https://github.com/mizorewww/Rayon/issues

If what Rayon sends ever changes, this policy, the schema in the source code and the App Store privacy label change in the same release.
