// The dashboard: one page and one summary query. Cloudflare Access stands in
// front of /dashboard* and signs in the members of the Access group; this
// Worker checks Access's token again, so a gap in the Access application
// never opens the data. The summary holds only sums over the range with
// every cell under the minimum left out, as the aggregates export does; no
// report or crash item leaves the database.
import { createRemoteJWKSet, jwtVerify } from "jose";
import page from "./dashboard.html";

export interface DashboardEnv {
  DB: D1Database;
  /** The Zero Trust team domain, e.g. https://<team>.cloudflareaccess.com. Not secret. */
  ACCESS_TEAM_DOMAIN?: string;
  /** The Access application's AUD tag. Not secret. */
  ACCESS_AUD?: string;
}

// One key set per team, kept for the isolate's life; jose refetches it when a token names a new key.
const keySets = new Map<string, ReturnType<typeof createRemoteJWKSet>>();

/** The signed-in email when the request carries a valid Access token for this application. */
async function viewer(request: Request, env: DashboardEnv): Promise<string | undefined> {
  const token = request.headers.get("cf-access-jwt-assertion");
  const team = env.ACCESS_TEAM_DOMAIN;
  if (!token || !team || !env.ACCESS_AUD) return undefined;
  let keys = keySets.get(team);
  if (!keys) keySets.set(team, (keys = createRemoteJWKSet(new URL("/cdn-cgi/access/certs", team))));
  try {
    const { payload } = await jwtVerify(token, keys, { issuer: team, audience: env.ACCESS_AUD, algorithms: ["RS256"], requiredClaims: ["exp", "iat"] });
    return typeof payload.email === "string" ? payload.email : "";
  } catch {
    return undefined;
  }
}

const isDay = (d: string) => /^\d{4}-\d{2}-\d{2}$/.test(d) && !Number.isNaN(Date.parse(d));
const utcDay = (date: Date) => date.toISOString().slice(0, 10);

async function summary(url: URL, env: DashboardEnv, minimumCount: number, email: string): Promise<Response> {
  const from = url.searchParams.get("from") ?? utcDay(new Date(Date.now() - 29 * 86_400_000));
  const to = url.searchParams.get("to") ?? utcDay(new Date());
  if (!isDay(from) || !isDay(to) || from > to) return Response.json({ error: "from and to are YYYY-MM-DD, from first" }, { status: 400 });

  const reports = "metric = 'reports' AND day BETWEEN ?1 AND ?2";
  const inRange = "day BETWEEN ?1 AND ?2";
  // Versions with fewer reports (or items) than the minimum in the range count as "other".
  const folded = (column: string, table: string, total: string, where: string) =>
    `CASE WHEN ${column} IN (SELECT ${column} FROM ${table} WHERE ${where} GROUP BY ${column} HAVING ${total} >= ?3) THEN ${column} ELSE 'other' END`;
  const share = (name: string) =>
    `SELECT ${name} AS name, SUM(count) AS count FROM aggregates WHERE ${reports} GROUP BY 1 HAVING SUM(count) >= ?3 ORDER BY count DESC`;
  const queries = {
    daily: `SELECT day, bucket, SUM(count) AS count FROM aggregates WHERE ${reports}
            GROUP BY day, bucket HAVING SUM(count) >= ?3 ORDER BY day`,
    metrics: `SELECT metric, bucket, SUM(count) AS count FROM aggregates WHERE ${inRange}
              GROUP BY metric, bucket HAVING SUM(count) >= ?3 ORDER BY metric, bucket`,
    appVersions: share(folded("app_version", "aggregates", "SUM(count)", reports)),
    osVersions: share(folded("os_version", "aggregates", "SUM(count)", reports)),
    platforms: share("substr(os_version, 1, instr(os_version, ' ') - 1)"),
    crashes: `SELECT kind, signature, ${folded("app_version", "crashes", "COUNT(*)", inRange)} AS appVersion, COUNT(*) AS count
              FROM crashes WHERE ${inRange} GROUP BY 1, 2, 3 HAVING COUNT(*) >= ?3 ORDER BY count DESC LIMIT 200`,
  };
  const names = Object.keys(queries) as (keyof typeof queries)[];
  const results = await env.DB.batch(names.map((name) => env.DB.prepare(queries[name]).bind(from, to, minimumCount)));
  return Response.json(
    { from, to, minimumCount, viewer: email, ...Object.fromEntries(names.map((name, i) => [name, results[i].results])) },
    { headers: { "cache-control": "no-store" } },
  );
}

export async function dashboard(request: Request, url: URL, env: DashboardEnv, minimumCount: number): Promise<Response> {
  const email = await viewer(request, env);
  if (email === undefined) return new Response(null, { status: 403 });
  if (request.method !== "GET") return new Response(null, { status: 405 });
  if (url.pathname === "/dashboard/api/summary") return summary(url, env, minimumCount, email);
  if (url.pathname !== "/dashboard" && url.pathname !== "/dashboard/") return new Response(null, { status: 404 });
  const nonce = btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(16))));
  return new Response(page.replaceAll("{{nonce}}", nonce), {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "content-security-policy": `default-src 'none'; script-src 'nonce-${nonce}'; style-src 'nonce-${nonce}'; connect-src 'self'; img-src data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`,
      "cache-control": "no-store",
      "referrer-policy": "no-referrer",
      "x-content-type-options": "nosniff",
    },
  });
}
