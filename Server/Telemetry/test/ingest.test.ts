import { createScheduledController, env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import worker from "../src/index";
// The Swift client's schema snapshot: what the app really sends.
import samples from "../../../Foundation/Telemetry/Tests/TelemetryTests/Fixtures/report-sample.json";

type Sample = (typeof samples)[number] & Record<string, unknown>;
const clone = <T>(value: T): T => structuredClone(value);
const withNonce = (sample: Sample, n: number) => ({ ...clone(sample), nonce: `00000000-0000-4000-8000-${String(n).padStart(12, "0")}` });

const post = (body: unknown, headers: Record<string, string> = {}) =>
  worker.fetch(
    new Request("https://telemetry.test/v1/reports", {
      method: "POST",
      headers: { "content-type": "application/json", ...headers },
      body: typeof body === "string" ? body : JSON.stringify(body),
    }),
    env,
  );

const read = (path: string, secret = "test-secret") =>
  worker.fetch(new Request(`https://telemetry.test${path}`, { headers: { authorization: `Bearer ${secret}` } }), env);

const dump = async () => {
  const tables = ["aggregates", "crashes", "nonces"];
  const rows = await Promise.all(tables.map((t) => env.DB.prepare(`SELECT * FROM ${t}`).all()));
  return JSON.stringify(rows.map((r) => r.results));
};

beforeEach(async () => {
  await env.DB.batch(["aggregates", "crashes", "nonces"].map((t) => env.DB.prepare(`DELETE FROM ${t}`)));
});

describe("ingest", () => {
  it("takes the app's sample reports and keeps only aggregates and crash items", async () => {
    const response = await post(
      { reports: samples },
      { "CF-Connecting-IP": "203.0.113.77", "User-Agent": "Mozilla/5.0 secret-agent", "X-Forwarded-For": "198.51.100.4" },
    );
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ accepted: 2 });

    const count = async (metric: string, bucket: string) =>
      (await env.DB.prepare("SELECT SUM(count) AS n FROM aggregates WHERE metric = ? AND bucket = ?").bind(metric, bucket).first<{ n: number }>())?.n;
    expect(await count("reports", "usage")).toBe(1);
    expect(await count("reports", "diagnostics")).toBe(1);
    expect(await count("usage.counts.terminalSessionsOpened", "6")).toBe(1);
    expect(await count("usage.keyTypes.ed25519", "true")).toBe(1);
    expect(await count("usage.counts.vncSessions", "0")).toBeNull();
    expect(await count("diagnostics", "crash")).toBe(2);
    const row = await env.DB.prepare("SELECT app_version, os_version FROM aggregates LIMIT 1").first();
    expect(row).toEqual({ app_version: "5.2.0", os_version: "macOS 15.4" });
    const crashes = await env.DB.prepare("SELECT COUNT(*) AS n FROM crashes").first<{ n: number }>();
    expect(crashes?.n).toBe(2);
    const signatures = await env.DB.prepare("SELECT DISTINCT signature FROM crashes").all<{ signature: string }>();
    expect(signatures.results.map((r) => r.signature)).toContain("crash NSInvalidArgumentException EXC 1 SIG 11 70B89F27+0x285b8");

    const stored = await dump();
    for (const leaked of ["203.0.113.77", "198.51.100.4", "secret-agent", "Mozilla"]) expect(stored).not.toContain(leaked);
  });

  it("counts a retried report once", async () => {
    await post({ reports: [samples[0]] });
    await post({ reports: [samples[0]] });
    const row = await env.DB.prepare("SELECT count FROM aggregates WHERE metric = 'reports'").first<{ count: number }>();
    expect(row?.count).toBe(1);
  });

  it("counts a report whose first write failed when it is retried", async () => {
    // The aggregate writes fail after the nonce statements are prepared.
    await env.DB.exec("CREATE TRIGGER fail_aggregates BEFORE INSERT ON aggregates BEGIN SELECT RAISE(ABORT, 'test failure'); END");
    try {
      await expect(post({ reports: [samples[0]] })).rejects.toThrow();
    } finally {
      await env.DB.exec("DROP TRIGGER fail_aggregates");
    }
    expect(await dump()).toBe("[[],[],[]]");

    expect((await post({ reports: [samples[0]] })).status).toBe(200);
    const row = await env.DB.prepare("SELECT count FROM aggregates WHERE metric = 'reports'").first<{ count: number }>();
    expect(row?.count).toBe(1);
  });

  it("counts a report sent twice in one batch once", async () => {
    await post({ reports: [samples[0], samples[0]] });
    const row = await env.DB.prepare("SELECT count FROM aggregates WHERE metric = 'reports'").first<{ count: number }>();
    expect(row?.count).toBe(1);
  });

  it.each<[string, (r: Sample) => void]>([
    ["an unknown key", (r) => (r.hostname = "db.example.com")],
    ["an unknown nested key", (r) => ((r.usage as Record<string, unknown>).lastHost = "10.0.0.1")],
    ["an enum value that is not a string", (r) => ((r as Record<string, unknown>).language = 7)],
    ["a string where a bucket goes", (r) => ((r.usage as { savedHosts: unknown }).savedHosts = "12")],
    ["a count below every bucket", (r) => ((r.usage as { savedHosts: unknown }).savedHosts = -1)],
    ["a count that is not an integer", (r) => ((r.usage as { savedHosts: unknown }).savedHosts = 2.5)],
    ["a wrong type in a map keyed by an enum", (r) => ((r.usage as { counts: Record<string, unknown> }).counts.editorOpened = "6")],
    ["a missing feature", (r) => delete (r.usage as { counts: Record<string, unknown> }).counts.editorOpened],
    ["a debug build", (r) => (r.channel = "debug")],
    ["level 0", (r) => (r.level = 0)],
    ["usage at level 1", (r) => (r.level = 1)],
    ["a full OS version", (r) => (r.osVersion = "15.4.1")],
    ["a free string in a frame", (r) => ((r.diagnostics as { callStacks: { frames: Record<string, unknown>[] }[] }[])[0].callStacks[0].frames[0].binaryName = "Rayon")],
    ["a time stamp", (r) => (r.date = "2026-11-27T10:00:00Z")],
  ])("rejects %s", async (_, change) => {
    const bad = clone(samples[0]) as Sample;
    change(bad);
    expect((await post({ reports: [bad] })).status).toBe(422);
    expect(await dump()).toBe("[[],[],[]]");
  });

  it("counts an enum value it does not know as other, without storing it", async () => {
    const r = clone(samples[0]) as Sample;
    r.language = "tlh";
    r.deviceClass = "vision-pro";
    r.usage!.redactionMode = "db.example.com";
    expect((await post({ reports: [r] })).status).toBe(200);
    const buckets = await env.DB.prepare("SELECT metric, bucket FROM aggregates WHERE metric IN ('language', 'deviceClass', 'usage.redactionMode')").all();
    expect(buckets.results).toEqual(expect.arrayContaining(["language", "deviceClass", "usage.redactionMode"].map((metric) => ({ metric, bucket: "other" }))));
    const stored = await dump();
    for (const leaked of ["tlh", "vision-pro", "db.example.com"]) expect(stored).not.toContain(leaked);
  });

  it("drops a key it does not know in a map keyed by an enum, without storing it", async () => {
    const r = clone(samples[0]) as Sample;
    (r.usage!.counts as Record<string, unknown>).aiChatsOpened = 6;
    (r.usage!.authMethodUsed as Record<string, unknown>).passkey = true;
    expect((await post({ reports: [r] })).status).toBe(200);
    expect(await env.DB.prepare("SELECT 1 FROM aggregates WHERE metric = 'usage.counts.terminalSessionsOpened'").first()).not.toBeNull();
    const stored = await dump();
    for (const leaked of ["aiChatsOpened", "passkey"]) expect(stored).not.toContain(leaked);
  });

  it("counts a bucket step it does not know in the known step below it", async () => {
    const r = clone(samples[0]) as Sample;
    r.usage!.savedHosts = 12;
    r.usage!.counts.editorOpened = 5000;
    (r.detail as { metrics: Record<string, number> }).metrics.launchTime = 450;
    expect((await post({ reports: [r] })).status).toBe(200);
    const bucket = async (metric: string) =>
      (await env.DB.prepare("SELECT bucket FROM aggregates WHERE metric = ?").bind(metric).first<{ bucket: string }>())?.bucket;
    expect(await bucket("usage.savedHosts")).toBe("6");
    expect(await bucket("usage.counts.editorOpened")).toBe("101");
    expect(await bucket("detail.metrics.launchTime")).toBe("300");
  });

  it.each(["ja", "fr", "es"])("takes the language %s", async (language) => {
    const r = clone(samples[1]) as Sample;
    r.language = language;
    expect((await post({ reports: [r] })).status).toBe(200);
    expect(await env.DB.prepare("SELECT bucket FROM aggregates WHERE metric = 'language'").first()).toEqual({ bucket: language });
  });

  it("refuses what is not a batch of one to ten reports", async () => {
    expect((await post("not json")).status).toBe(400);
    expect((await post({ reports: [] })).status).toBe(400);
    expect((await post({ reports: Array.from({ length: 11 }, (_, i) => withNonce(samples[1], i)) })).status).toBe(400);
    expect((await post({ reports: [samples[0]], extra: 1 })).status).toBe(400);
    expect((await post("x".repeat(300 * 1024))).status).toBe(413);
    expect((await worker.fetch(new Request("https://telemetry.test/v1/reports"), env)).status).toBe(405);
  });
});

describe("read", () => {
  it("needs the secret", async () => {
    expect((await read("/v1/aggregates", "wrong")).status).toBe(401);
    expect((await worker.fetch(new Request("https://telemetry.test/v1/aggregates"), env)).status).toBe(401);
  });

  it("leaves out cells with fewer than ten reports and folds rare versions", async () => {
    const reports = Array.from({ length: 10 }, (_, i) => withNonce(samples[0], i));
    reports[0].usage!.counts.editorOpened = 101;
    reports[9].appVersion = "4.9.0";
    await post({ reports });

    const response = await read("/v1/aggregates");
    expect(response.status).toBe(200);
    const { rows } = (await response.json()) as { rows: { appVersion: string; metric: string; bucket: string; count: number }[] };
    expect(rows.every((r) => r.count >= 10)).toBe(true);
    // Nine reports of 5.2.0 and one of 4.9.0: neither version reaches ten, so both fold into "other".
    expect(rows.find((r) => r.metric === "reports")).toMatchObject({ appVersion: "other", bucket: "usage", count: 10 });
    expect(rows.some((r) => r.metric === "usage.counts.editorOpened" && r.bucket === "101")).toBe(false);
  });

  it("lists crash items", async () => {
    await post({ reports: [samples[1]] });
    const { items } = (await (await read("/v1/crashes?from=2000-01-01")).json()) as { items: { kind: string; item: { callStacks: unknown[] } }[] };
    expect(items).toHaveLength(1);
    expect(items[0].kind).toBe("crash");
    expect(items[0].item.callStacks).toHaveLength(1);
  });
});

describe("retention", () => {
  it("deletes crash items after 90 days and old nonces", async () => {
    await env.DB.batch([
      env.DB.prepare("INSERT INTO crashes (day, app_version, os_version, kind, item) VALUES ('2000-01-01', '1.0.0', 'macOS 15.0', 'crash', '{}')"),
      env.DB.prepare("INSERT INTO nonces (nonce, day) VALUES ('old', '2000-01-01')"),
    ]);
    await post({ reports: [samples[1]] });
    await worker.scheduled(createScheduledController(), env);
    const days = await env.DB.prepare("SELECT day FROM crashes").all<{ day: string }>();
    expect(days.results.map((r) => r.day)).not.toContain("2000-01-01");
    expect(days.results).toHaveLength(1);
    expect(await env.DB.prepare("SELECT * FROM nonces WHERE nonce = 'old'").first()).toBeNull();
  });
});
