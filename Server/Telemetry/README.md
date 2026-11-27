# Rayon telemetry Worker

The ingest for Rayon's anonymous telemetry, as specified in [`docs/telemetry.md`](../../docs/telemetry.md): a Cloudflare Worker with a D1 database.

- `POST /v1/reports` takes `{"reports": [...]}`, one to ten reports the app built (`Foundation/Telemetry`). Each report is checked against the client's schema snapshot (`Foundation/Telemetry/Tests/TelemetryTests/Fixtures/report-enums.json`). Unknown keys, unknown values and free strings are rejected with 422.
- Accepted reports are folded into `aggregates` (day × app version × OS version × metric × bucket → count) and dropped. Zero counts and `false` flags are not written; they follow from the `reports` totals. Crash and hang items go to `crashes`, which keeps them 90 days for symbolication.
- A report's `nonce` is kept three days so that a retried report is counted once. It is the only per-report value stored, and it is random.
- The Worker never reads `CF-Connecting-IP`, `X-Forwarded-For` or `User-Agent`. Workers Logs, invocation logs, Logpush and `workers.dev` are off in `wrangler.toml`.
- `GET /v1/aggregates?from=YYYY-MM-DD&to=YYYY-MM-DD` and `GET /v1/crashes?from=YYYY-MM-DD` need `Authorization: Bearer <READ_SECRET>`. Aggregates fold app and OS versions with fewer than ten reports in the range into `other`, and leave out every cell under ten.
- A daily cron deletes crash items older than 90 days and nonces older than three days.

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

Cloudflare's free plan covers the volume in `docs/telemetry.md` §4.8. Serve the Worker only on a domain of your own: `workers.dev` is unreliable from mainland China.

1. Sign in: `bunx wrangler login`.
2. Create the database next to most users. `apac` suits mainland China and the rest of Asia; `weur` or `enam` suit others:
   ```sh
   bunx wrangler d1 create rayon-telemetry --location apac
   ```
   Put the `database_id` it prints into `wrangler.toml`.
3. Create the tables: `bun run migrate:remote`.
4. Set the read secret. Keep it in a password manager; it opens the aggregates and crash items:
   ```sh
   openssl rand -base64 32 | bunx wrangler secret put READ_SECRET
   ```
5. Route the Worker on your domain. The zone must be on Cloudflare with a proxied DNS record for the host (for example an `AAAA` record to `100::`). In `wrangler.toml`, uncomment `routes` and fill in your host and zone:
   ```toml
   routes = [{ pattern = "telemetry.example.com/v1/*", zone_name = "example.com" }]
   ```
6. Deploy: `bun run deploy`.
7. In the Cloudflare dashboard, check that the zone has no Logpush job for this host. Also check that Web Analytics and the Workers Observability log views are off for it.
8. Check that the Worker answers: `curl -i https://telemetry.example.com/v1/reports` should return `405`.
9. Point the app at it. In `Foundation/Telemetry/Sources/Telemetry/TelemetryEndpoint.swift`, set `url` to `https://telemetry.example.com/v1/reports`. Sending turns on in Release builds once the host is no longer the placeholder.
10. Before the release that ships this, update the App Store privacy label in App Store Connect from `docs/telemetry.md`, and publish the privacy policy (`Resources/AppStore/PrivacyPolicy`).

Read the counts:

```sh
curl -H "Authorization: Bearer $READ_SECRET" "https://telemetry.example.com/v1/aggregates?from=2026-12-01&to=2026-12-31"
```

The `reports` metric with bucket `usage` counts daily reports, which approximates daily active devices at level 2 and up. Every other metric is a count of reports per bucket. For example, `usage.counts.terminalSessionsOpened` with bucket `6` is the number of devices that opened 6–20 terminal sessions that day.

## Changing the schema

The Swift report is the source of truth. Change it, record the snapshot (`TELEMETRY_RECORD_SNAPSHOT=1 swift test --package-path Foundation/Telemetry`), run this Worker's tests and redeploy before the app ships. Update `docs/telemetry.md`, the privacy policy, the privacy manifest and the App Store label in the same change. A new field or case is rejected by a Worker that has not been redeployed, and the app drops the reports it rejects.
