# Rayon telemetry Worker

The ingest for Rayon's anonymous telemetry, as specified in [`docs/telemetry.md`](../../docs/telemetry.md): a Cloudflare Worker with a D1 database.

- `POST /v1/reports` takes `{"reports": [...]}`, one to ten reports the app built (`Foundation/Telemetry`). Each report is checked against the client's schema snapshot (`Foundation/Telemetry/Tests/TelemetryTests/Fixtures/report-enums.json`). Unknown keys, free strings and values of the wrong type are rejected with 422. What a newer app may add is let through: an enum value the Worker does not know yet is counted as `other`, a key it does not know inside a map keyed by an enum (such as `usage.counts`) is dropped, and a bucket step it does not know is counted in the known step below it. The unknown value itself is not stored.
- Accepted reports are folded into `aggregates` (day × app version × OS version × metric × bucket → count) and dropped. Zero counts and `false` flags are not written; they follow from the `reports` totals. Crash and hang items go to `crashes`, which keeps them 90 days for symbolication.
- A report's `nonce` is kept three days so that a retried report is counted once. It is the only per-report value stored, and it is random.
- The Worker never reads `CF-Connecting-IP`, `X-Forwarded-For` or `User-Agent`. Workers Logs, traces, Logpush and `workers.dev` are off in `cloudflare.config.ts` (deploy) and `wrangler.toml` (local).
- `GET /v1/aggregates?from=YYYY-MM-DD&to=YYYY-MM-DD` and `GET /v1/crashes?from=YYYY-MM-DD` need `Authorization: Bearer <READ_SECRET>`. Aggregates fold app and OS versions with fewer than ten reports in the range into `other`, and leave out every cell under ten.
- A daily cron deletes crash items older than 90 days and nonces older than three days.
- `GET /dashboard` is a page over the same sums, behind Cloudflare Access ([Dashboard](#dashboard)).

## Develop

[bun](https://bun.sh) runs everything. `WRANGLER_SEND_METRICS=false` keeps wrangler's own usage reporting off.

```sh
cd Server/Telemetry
bun install
bun run test          # Vitest inside workerd (@cloudflare/vitest-plugin), on a local D1
bun run typecheck
```

From the repository root, `make test-telemetry-server` runs both.

To see the app's sender reach a local Worker:

```sh
bun run migrate:local
bun run dev           # http://127.0.0.1:8787, local D1 in .wrangler/
# in another shell, from the repository root:
TELEMETRY_LIVE_ENDPOINT=http://127.0.0.1:8787/v1/reports \
  swift test --package-path Foundation/Telemetry --filter LiveEndpoint
bunx wrangler d1 execute rayon-telemetry --local --command "SELECT * FROM aggregates"
```

## Deploy

The Worker runs at `https://telemetry.kfcv50.today`, a custom domain on the `kfcv50.today` zone, with database `rayon-telemetry` (`90d72dcf-b4c1-4bb8-8322-5ee7ae53757a`, APAC). It is not on `workers.dev`, which is unreliable from mainland China. Cloudflare's free plan covers the volume in `docs/telemetry.md` §4.8.

Everything that touches the account goes through the Cloudflare CLI `cf`, pinned in `package.json` (`bunx cf` runs it). `cf deploy` reads `cloudflare.config.ts`; `wrangler.toml` only serves `wrangler dev` and the tests. Set `CF_SEND_TELEMETRY=false` to keep cf's own usage reporting off.

How it was first deployed (2026-11-27):

1. Sign in once: `bunx cf auth login`. Check with `bunx cf auth whoami`.
2. Create the database next to most users:
   ```sh
   bunx cf d1 create --name rayon-telemetry --primary-location-hint apac
   ```
   Its id goes into `cloudflare.config.ts`, `wrangler.toml` and the `migrate:remote` script.
3. Create the tables: `bun run migrate:remote` (`cf d1 migrations apply <id> --dir migrations`).
4. Deploy the first time with the read secret, which a Worker that does not exist yet cannot get any other way. The secret file is temporary and outside the repository; keep the secret in a password manager (it opens the aggregates and crash items):
   ```sh
   umask 077
   printf 'READ_SECRET=%s\n' "$(openssl rand -hex 32)" > /tmp/rayon-telemetry.env
   bunx cf deploy --secrets-file /tmp/rayon-telemetry.env
   rm /tmp/rayon-telemetry.env
   ```
   `cf deploy` builds the Worker, uploads it with the D1 binding, attaches the custom domain `telemetry.kfcv50.today` (Cloudflare creates its DNS record and certificate), turns `workers.dev` and preview URLs off and installs the daily cron.
5. Check the result:
   ```sh
   bunx cf workers get rayon-telemetry      # observability.enabled, logs.enabled, traces.enabled, logpush: false; subdomain.enabled: false; domains: telemetry.kfcv50.today
   bunx cf workers secrets list --worker rayon-telemetry   # READ_SECRET, secret_text
   curl -i https://telemetry.kfcv50.today/v1/reports        # 405
   curl -i https://telemetry.kfcv50.today/v1/aggregates     # 401
   ```
6. In the Cloudflare dashboard, check that the zone has no Logpush job for this host and that Web Analytics is off for it.
7. Before the release that ships this, update the App Store privacy label in App Store Connect from `docs/telemetry.md` §5.3, and publish the privacy policy (`Resources/AppStore/PrivacyPolicy`).

Later deploys are `bun run test && bun run deploy`. To replace the read secret: `bunx cf workers secrets update --worker rayon-telemetry --type secret_text` (see `--help`).

To check the live Worker end to end, post one sample report (app version `0.0.0`, which no release has; its nonce row expires on its own after three days) with the app's sender, read it back, and delete it:

```sh
TELEMETRY_LIVE_ENDPOINT=https://telemetry.kfcv50.today/v1/reports \
  swift test --package-path Foundation/Telemetry --filter LiveEndpoint
curl -H "Authorization: Bearer $READ_SECRET" "https://telemetry.kfcv50.today/v1/crashes?from=$(date -u +%F)"
bunx cf d1 query 90d72dcf-b4c1-4bb8-8322-5ee7ae53757a --sql "SELECT * FROM aggregates WHERE app_version = '0.0.0'"
bunx cf d1 query 90d72dcf-b4c1-4bb8-8322-5ee7ae53757a --sql "DELETE FROM aggregates WHERE app_version = '0.0.0'; DELETE FROM crashes WHERE app_version = '0.0.0'"
```

The aggregates endpoint hides cells under ten, so a single report shows only in `/v1/crashes` and in D1.

Read the counts:

```sh
curl -H "Authorization: Bearer $READ_SECRET" "https://telemetry.kfcv50.today/v1/aggregates?from=2026-12-01&to=2026-12-31"
```

The `reports` metric with bucket `usage` counts daily reports, which approximates daily active devices at level 2 and up. Every other metric is a count of reports per bucket. For example, `usage.counts.terminalSessionsOpened` with bucket `6` is the number of devices that opened 6–20 terminal sessions that day.

## Dashboard

`https://telemetry.kfcv50.today/dashboard` shows, for a range of days: daily reports, reports by app version, platform, OS version, device class, language, region group, channel and telemetry level, feature usage, connection outcomes, settings, level 3 detail, and crash and hang items counted by signature and app version.

It reads one query, `GET /dashboard/api/summary?from=YYYY-MM-DD&to=YYYY-MM-DD`, which sums `aggregates` and `crashes` over the range and leaves out every cell under ten, as `/v1/aggregates` does; app and OS versions under ten fold into `other`. No report or crash item leaves the database. A crash item's signature (kind, exception, first app frame of the attributed thread) is computed at ingest (`src/signature.ts`) and kept in `crashes.signature`.

### Sign in

Cloudflare Zero Trust Access guards `/dashboard` and everything under it; `/v1/*` stays outside, so ingest is unaffected. In Zero Trust (team `djtrump.cloudflareaccess.com`):

- Access › Applications › **Rayon telemetry dashboard**: self-hosted, destination `telemetry.kfcv50.today/dashboard`, 24-hour sessions, and one login method: the **Cloudflare** identity provider (Settings › Authentication), limited to members of this Cloudflare account. Opening the page goes straight to its login.
- Its policy **Rayon telemetry admins** allows the group **Rayon telemetry team** (Access › Groups), which lists by email the people who may sign in.

Open the URL and sign in to Cloudflare as you do for the Cloudflare dashboard; the first time, approve Cloudflare Access's request to use your Cloudflare account. Sign out from the page, or at `/cdn-cgi/access/logout`.

- **Add a teammate**: two steps, since only account members can sign in and only the group's members are let in. Invite them to the Cloudflare account (Manage Account › Members › Invite; a read-only role is enough), then add the email they use for Cloudflare to Zero Trust › Access › Groups › Rayon telemetry team › Edit › Include › Emails, and Save. They sign in the same way.
- **Remove a teammate**: delete their email from that group, and remove them from the account's members if they need nothing else there. Sessions they already hold last up to 24 hours; to end them now, Zero Trust › My Team › Users › the user › Revoke session.

The Worker does not trust the route alone: on every `/dashboard*` request it verifies the `Cf-Access-Jwt-Assertion` token Access adds (signature against the team's keys at `/cdn-cgi/access/certs`, issuer, audience, and the `exp` and `iat` claims, which must be present) and answers a bare 403 otherwise. The team domain and the application's AUD tag are the `ACCESS_TEAM_DOMAIN` and `ACCESS_AUD` variables in `cloudflare.config.ts` and `wrangler.toml`. Neither is secret. If the application is recreated, copy its new AUD tag (Access › Applications › the app › Overview, "Application Audience (AUD) Tag") into both files and redeploy.

### Deploy

The page is `src/dashboard.html`, imported as text, with no build step of its own. A deploy that adds a migration applies it first:

```sh
bun run test && bun run migrate:remote && bun run deploy
curl -s -o /dev/null -w '%{http_code}\n' https://telemetry.kfcv50.today/dashboard   # 302 to the Access login
```

## Changing the schema

The Swift report is the source of truth. Change it, record the snapshot (`TELEMETRY_RECORD_SNAPSHOT=1 swift test --package-path Foundation/Telemetry`), run this Worker's tests and redeploy before the app ships. Update `docs/telemetry.md`, the privacy policy, the privacy manifest and the App Store label in the same change. A new field is rejected by a Worker that has not been redeployed, and the app drops the reports it rejects; a new enum case is counted as `other` until the Worker is redeployed.
