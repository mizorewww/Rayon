import { env } from "cloudflare:test";
import { exportJWK, generateKeyPair, SignJWT, type CryptoKey } from "jose";
import { beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import samples from "../../../Foundation/Telemetry/Tests/TelemetryTests/Fixtures/report-sample.json";

const team = "https://rayon-test.cloudflareaccess.com";
let accessKey: CryptoKey;
let strangerKey: CryptoKey;

beforeAll(async () => {
  const pair = await generateKeyPair("RS256", { extractable: true });
  strangerKey = (await generateKeyPair("RS256")).privateKey;
  accessKey = pair.privateKey;
  const jwk = { ...(await exportJWK(pair.publicKey)), kid: "access", alg: "RS256", use: "sig" };
  const realFetch = globalThis.fetch;
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) =>
    String(input instanceof Request ? input.url : input) === `${team}/cdn-cgi/access/certs` ? Response.json({ keys: [jwk] }) : realFetch(input, init),
  );
});

beforeEach(async () => {
  await env.DB.batch(["aggregates", "crashes", "nonces"].map((t) => env.DB.prepare(`DELETE FROM ${t}`)));
});

const token = (claims: { aud?: string; iss?: string; exp?: number | null; iat?: false; key?: CryptoKey } = {}) => {
  const jwt = new SignJWT({ email: "admin@example.com" })
    .setProtectedHeader({ alg: "RS256", kid: "access" })
    .setIssuer(claims.iss ?? team)
    .setAudience(claims.aud ?? "test-aud");
  if (claims.iat !== false) jwt.setIssuedAt();
  if (claims.exp !== null) jwt.setExpirationTime(claims.exp ?? "1h");
  return jwt.sign(claims.key ?? accessKey);
};

const get = (path: string, jwt?: string) =>
  worker.fetch(new Request(`https://telemetry.test${path}`, { headers: jwt ? { "cf-access-jwt-assertion": jwt } : {} }), env);

const post = (reports: unknown[]) =>
  worker.fetch(new Request("https://telemetry.test/v1/reports", { method: "POST", body: JSON.stringify({ reports }) }), env);
const withNonce = <T extends object>(sample: T, n: number) => ({ ...structuredClone(sample), nonce: `00000000-0000-4000-8000-${String(n).padStart(12, "0")}` });

describe("dashboard", () => {
  it.each<[string, () => Promise<string | undefined>]>([
    ["no token", async () => undefined],
    ["a token signed by another key", () => token({ key: strangerKey })],
    ["a token for another application", () => token({ aud: "other-app" })],
    ["a token from another team", () => token({ iss: "https://elsewhere.cloudflareaccess.com" })],
    ["an expired token", () => token({ exp: Math.floor(Date.now() / 1000) - 600 })],
    ["a token without an expiry", () => token({ exp: null })],
    ["a token without an issue time", () => token({ iat: false })],
    ["a token that is not a JWT", async () => "not-a-jwt"],
  ])("refuses %s with a bare 403", async (_, make) => {
    for (const path of ["/dashboard", "/dashboard/api/summary", "/dashboard/anything"]) {
      const response = await get(path, await make());
      expect(response.status).toBe(403);
      expect(await response.text()).toBe("");
    }
  });

  it("does not take the token from a cookie or the query", async () => {
    const jwt = await token();
    const cookie = await worker.fetch(new Request("https://telemetry.test/dashboard", { headers: { cookie: `CF_Authorization=${jwt}` } }), env);
    expect(cookie.status).toBe(403);
    expect((await get(`/dashboard?token=${jwt}`)).status).toBe(403);
  });

  it("serves the page under a strict content security policy", async () => {
    const response = await get("/dashboard", await token());
    expect(response.status).toBe(200);
    const csp = response.headers.get("content-security-policy") ?? "";
    const nonce = /'nonce-([^']+)'/.exec(csp)?.[1];
    expect(nonce).toBeTruthy();
    expect(csp).toContain("default-src 'none'");
    const html = await response.text();
    expect(html).toContain(`<script nonce="${nonce}">`);
    expect(html).not.toContain("{{nonce}}");
  });

  it("sums the range and leaves out every cell under ten", async () => {
    // Thirteen diagnostics reports, three of them from a build that stays under the minimum, and four usage reports.
    const reports = Array.from({ length: 13 }, (_, i) => withNonce(samples[1], i));
    for (const r of reports.slice(10)) r.appVersion = "4.9.0";
    await post(reports.slice(0, 10));
    await post(reports.slice(10));
    await post(Array.from({ length: 4 }, (_, i) => withNonce(samples[0], 100 + i)));

    const response = await get("/dashboard/api/summary?from=2000-01-01&to=2100-01-01", await token());
    expect(response.status).toBe(200);
    const data = (await response.json()) as Record<string, { count: number; [key: string]: unknown }[]> & { viewer: string };
    expect(data.viewer).toBe("admin@example.com");
    for (const key of ["daily", "metrics", "appVersions", "osVersions", "platforms", "crashes"]) {
      expect(data[key].every((r) => r.count >= 10)).toBe(true);
    }
    expect(data.daily).toEqual([expect.objectContaining({ bucket: "diagnostics", count: 13 })]);
    // 5.2.0 reaches ten reports; 4.9.0 has three and folds into other, which stays under ten.
    expect(data.appVersions).toEqual([{ name: "5.2.0", count: 14 }]);
    expect(data.platforms).toEqual([{ name: "macOS", count: 17 }]);
    expect(data.metrics).toContainEqual({ metric: "language", bucket: "en", count: 17 });
    expect(data.metrics.some((r) => r.metric === "usage.counts.terminalSessionsOpened")).toBe(false);
    // A crash item counts under its own app version, which all seventeen give as 5.2.0.
    expect(data.crashes).toEqual([
      { kind: "crash", signature: "crash NSInvalidArgumentException EXC 1 SIG 11 70B89F27+0x285b8", appVersion: "5.2.0", count: 17 },
    ]);
    expect(JSON.stringify(data)).not.toContain("callStacks");
  });

  it("checks the range", async () => {
    const jwt = await token();
    expect((await get("/dashboard/api/summary?from=2026-12-01&to=2026-11-01", jwt)).status).toBe(400);
    expect((await get("/dashboard/api/summary?from=yesterday", jwt)).status).toBe(400);
  });

  it("leaves ingest outside", async () => {
    expect((await post([withNonce(samples[0], 900)])).status).toBe(200);
  });
});
