// The dashboard: one page and one summary query. Cloudflare Access stands in
// front of /dashboard* and signs in the members of the Access group; this
// Worker checks Access's token again, so a gap in the Access application
// never opens the data. The summary holds only range sums of per-day cells
// that reach the minimum, as the aggregates export thresholds each day; no
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

  // Every cell is thresholded per day before it enters a range total, so no
  // range differs from another by a day's cell under the minimum: subtracting
  // two overlapping ranges gives back only sums of cells the per-day view
  // shows anyway. Versions under the minimum on a day fold into "other" that
  // day, for the same reason.
  const inRange = "day BETWEEN ?1 AND ?2";
  const reports = `metric = 'reports' AND ${inRange}`;
  const share = (name: string) =>
    `WITH cells AS (SELECT day, ${name} AS name, SUM(count) AS count FROM aggregates WHERE ${reports} GROUP BY 1, 2),
          kept AS (SELECT day, CASE WHEN count >= ?3 THEN name ELSE 'other' END AS name, SUM(count) AS count
                   FROM cells GROUP BY 1, 2 HAVING SUM(count) >= ?3)
     SELECT name, SUM(count) AS count FROM kept GROUP BY name ORDER BY count DESC`;
  const queries = {
    daily: `SELECT day, bucket, SUM(count) AS count FROM aggregates WHERE ${reports}
            GROUP BY day, bucket HAVING SUM(count) >= ?3 ORDER BY day`,
    metrics: `WITH kept AS (SELECT day, metric, bucket, SUM(count) AS count FROM aggregates WHERE ${inRange}
                            GROUP BY 1, 2, 3 HAVING SUM(count) >= ?3)
              SELECT metric, bucket, SUM(count) AS count FROM kept GROUP BY 1, 2 ORDER BY metric, bucket`,
    appVersions: share("app_version"),
    osVersions: share("os_version"),
    platforms: share("substr(os_version, 1, instr(os_version, ' ') - 1)"),
    // A crash cell counts distinct reports, not items: one device crash-looping
    // within a report fills no cell on its own.
    crashes: `WITH versions AS (SELECT day, app_version FROM crashes WHERE ${inRange} GROUP BY 1, 2 HAVING COUNT(DISTINCT report) >= ?3),
                   kept AS (SELECT c.day, c.kind, c.signature, CASE WHEN v.day IS NULL THEN 'other' ELSE c.app_version END AS appVersion,
                                   COUNT(DISTINCT c.report) AS count
                            FROM crashes c LEFT JOIN versions v ON v.day = c.day AND v.app_version = c.app_version
                            WHERE c.${inRange} GROUP BY 1, 2, 3, 4 HAVING COUNT(DISTINCT c.report) >= ?3)
              SELECT kind, signature, appVersion, SUM(count) AS count FROM kept GROUP BY 1, 2, 3 ORDER BY count DESC LIMIT 200`,
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
