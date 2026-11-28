// Rayon's telemetry ingest. docs/telemetry.md §4.3: no identifier, no IP
// and no User-Agent are ever read; each report is folded into daily
// aggregate counts and dropped. Only crash and hang items are kept as
// rows, for 90 days, to symbolicate.
import { batch, report, type Report } from "./schema";
import { signature } from "./signature";

export interface Env {
  DB: D1Database;
  /** `wrangler secret put READ_SECRET`; the read endpoints are closed without it. */
  READ_SECRET?: string;
}

const maxBody = 256 * 1024;
/** Cells with fewer reports than this are left out of exports. */
const minimumCount = 10;
const crashRetentionDays = 90;

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

const utcDay = (date = new Date()) => date.toISOString().slice(0, 10);
const daysAgo = (days: number) => utcDay(new Date(Date.now() - days * 86_400_000));

/** One row per (metric, bucket) the report counts in. Zeros and false are left out: they follow from the totals. */
function metrics(r: Report): [string, string][] {
  const rows: [string, string][] = [
    ["reports", r.usage ? "usage" : "diagnostics"],
    ["level", String(r.level)],
    ["channel", r.channel],
    ["deviceClass", r.deviceClass],
    ["language", r.language],
    ["regionGroup", r.regionGroup],
  ];
  const walk = (prefix: string, value: unknown) => {
    if (typeof value === "object" && value !== null) {
      for (const [key, inner] of Object.entries(value)) walk(`${prefix}.${key}`, inner);
    } else if (typeof value === "number" && value !== 0) {
      rows.push([prefix, String(value)]);
    } else if (value === true) {
      rows.push([prefix, "true"]);
    } else if (typeof value === "string") {
      rows.push([prefix, value]);
    }
  };
  if (r.usage) walk("usage", r.usage);
  if (r.detail) walk("detail", r.detail);
  for (const d of r.diagnostics) rows.push(["diagnostics", d.kind]);
  return rows;
}

async function ingest(request: Request, env: Env): Promise<Response> {
  const length = Number(request.headers.get("content-length") ?? "0");
  if (length > maxBody) return json({ error: "too large" }, 413);
  const text = await request.text();
  if (text.length > maxBody) return json({ error: "too large" }, 413);
  let body: unknown;
  try {
    body = JSON.parse(text);
  } catch {
    return json({ error: "not JSON" }, 400);
  }
  const envelope = batch.safeParse(body);
  if (!envelope.success) return json({ error: "not a batch" }, 400);
  const parsed = envelope.data.reports.map((item) => report.safeParse(item));
  if (parsed.some((p) => !p.success)) return json({ error: "invalid report" }, 422);
  const reports = parsed.map((p) => p.data as Report);

  const day = utcDay();
  // A retried report has the same nonce; only its first copy counts. Each
  // report's writes skip themselves once its nonce is there, and its nonce
  // is written after them, all in one batch, which D1 runs as one
  // transaction: a failure leaves no nonce claimed, so the client's retry
  // still counts.
  const unseen = "WHERE NOT EXISTS (SELECT 1 FROM nonces WHERE nonce = ?)";
  const upsert = env.DB.prepare(
    `INSERT INTO aggregates (day, app_version, os_version, metric, bucket, count) SELECT ?, ?, ?, ?, ?, 1 ${unseen}
     ON CONFLICT (day, app_version, os_version, metric, bucket) DO UPDATE SET count = count + 1`,
  );
  const crash = env.DB.prepare(`INSERT INTO crashes (day, app_version, os_version, kind, signature, item) SELECT ?, ?, ?, ?, ?, ? ${unseen}`);
  const claim = env.DB.prepare("INSERT INTO nonces (nonce, day) VALUES (?, ?) ON CONFLICT DO NOTHING");
  const statements: D1PreparedStatement[] = [];
  for (const r of reports) {
    const nonce = r.nonce.toLowerCase();
    const os = `${r.platform} ${r.osVersion}`;
    for (const [metric, bucket] of metrics(r)) statements.push(upsert.bind(day, r.appVersion, os, metric, bucket, nonce));
    for (const d of r.diagnostics) {
      statements.push(crash.bind(day, d.appVersion ?? r.appVersion, d.osVersion ? `${r.platform} ${d.osVersion}` : os, d.kind, signature(d), JSON.stringify(d), nonce));
    }
    statements.push(claim.bind(nonce, day));
  }
  await env.DB.batch(statements);
  return json({ accepted: reports.length });
}

async function authorized(request: Request, env: Env): Promise<boolean> {
  const given = new TextEncoder().encode(request.headers.get("authorization") ?? "");
  const expected = new TextEncoder().encode(`Bearer ${env.READ_SECRET ?? ""}`);
  if (!env.READ_SECRET || given.byteLength !== expected.byteLength) return false;
  return crypto.subtle.timingSafeEqual(given, expected);
}

/** Aggregates over a range of days, with rare versions folded into "other" and small cells left out. */
async function aggregates(url: URL, env: Env): Promise<Response> {
  const from = url.searchParams.get("from") ?? daysAgo(30);
  const to = url.searchParams.get("to") ?? utcDay();
  if (![from, to].every((d) => /^\d{4}-\d{2}-\d{2}$/.test(d))) return json({ error: "from and to are YYYY-MM-DD" }, 400);
  const { results } = await env.DB.prepare(
    `WITH apps AS (SELECT app_version FROM aggregates WHERE metric = 'reports' AND day BETWEEN ?1 AND ?2 GROUP BY app_version HAVING SUM(count) >= ?3),
          systems AS (SELECT os_version FROM aggregates WHERE metric = 'reports' AND day BETWEEN ?1 AND ?2 GROUP BY os_version HAVING SUM(count) >= ?3)
     SELECT day,
            CASE WHEN app_version IN (SELECT app_version FROM apps) THEN app_version ELSE 'other' END AS appVersion,
            CASE WHEN os_version IN (SELECT os_version FROM systems) THEN os_version ELSE 'other' END AS osVersion,
            metric, bucket, SUM(count) AS count
     FROM aggregates WHERE day BETWEEN ?1 AND ?2
     GROUP BY 1, 2, 3, 4, 5 HAVING SUM(count) >= ?3
     ORDER BY day, metric, bucket, appVersion, osVersion`,
  )
    .bind(from, to, minimumCount)
    .all();
  return json({ from, to, minimumCount, rows: results });
}

async function crashes(url: URL, env: Env): Promise<Response> {
  const from = url.searchParams.get("from") ?? daysAgo(7);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(from)) return json({ error: "from is YYYY-MM-DD" }, 400);
  const { results } = await env.DB.prepare(
    "SELECT day, app_version AS appVersion, os_version AS osVersion, kind, item FROM crashes WHERE day >= ? ORDER BY id LIMIT 1000",
  )
    .bind(from)
    .all<{ item: string }>();
  return json({ from, items: results.map((row) => ({ ...row, item: JSON.parse(row.item) })) });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/v1/reports") {
      return request.method === "POST" ? ingest(request, env) : json({ error: "POST only" }, 405);
    }
    if (request.method === "GET" && (url.pathname === "/v1/aggregates" || url.pathname === "/v1/crashes")) {
      if (!(await authorized(request, env))) return json({ error: "unauthorized" }, 401);
      return url.pathname === "/v1/aggregates" ? aggregates(url, env) : crashes(url, env);
    }
    return json({ error: "not found" }, 404);
  },

  async scheduled(_controller: ScheduledController, env: Env): Promise<void> {
    await env.DB.batch([
      env.DB.prepare("DELETE FROM crashes WHERE day < ?").bind(daysAgo(crashRetentionDays)),
      // A nonce only has to outlive the client's retries.
      env.DB.prepare("DELETE FROM nonces WHERE day < ?").bind(daysAgo(3)),
    ]);
  },
} satisfies ExportedHandler<Env>;
