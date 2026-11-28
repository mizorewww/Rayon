// The report the app sends, checked field by field. The enum cases come
// from the client's own schema snapshot, so the two cannot drift: a case
// added in Swift changes report-enums.json, and this Worker accepts it once
// redeployed. Unknown keys are rejected, except inside a map keyed by an
// enum, where a key this Worker does not know yet (a case added in a newer
// app) is dropped. An enum value it does not know yet is counted as "other",
// and a bucket step it does not know yet as the known step below it, rather
// than costing the client its whole report; the value itself is never stored.
import { z } from "zod";
import snapshot from "../../../Foundation/Telemetry/Tests/TelemetryTests/Fixtures/report-enums.json";

type Name = keyof typeof snapshot;

// Languages the client adds next; harmless once the snapshot lists them too.
const enums: Record<Name, string[]> = { ...snapshot, language: [...new Set([...snapshot.language, "ja", "fr", "es"])] };

const oneOf = (name: Name) => {
  const known = new Set(enums[name]);
  return z.string().transform((value) => (known.has(value) ? value : "other"));
};
// Every step is the lower bound of its bucket, so a value between two known steps
// (a step added in a newer app) honestly falls in the lower one.
const numberIn = (name: Name) => {
  const steps = enums[name].map(Number).sort((a, b) => b - a);
  return z
    .number()
    .int()
    .min(steps[steps.length - 1])
    .transform((n) => steps.find((step) => step <= n)!);
};
const bucket = numberIn("countBucket");
// z.object drops the keys it does not list.
const every = <T extends z.ZodType>(name: Name, value: T) =>
  z.object(Object.fromEntries(enums[name].map((key) => [key, value])) as Record<string, T>);

const appVersion = z.string().regex(/^\d{1,3}\.\d{1,3}\.\d{1,3}$/);
const osVersion = z.string().regex(/^\d{1,3}\.\d{1,3}$/);
const integer = z.number().int().min(-(2 ** 53)).max(2 ** 53);

export type Frame = { origin: string; binaryUUID?: string; offset?: number; sampleCount: number; subFrames: Frame[] };
const frame: z.ZodType<Frame> = z.lazy(() =>
  z.strictObject({
    origin: oneOf("frameOrigin"),
    binaryUUID: z.guid().optional(),
    offset: z.number().int().min(0).max(2 ** 53).optional(),
    sampleCount: z.number().int().min(0).max(1_000_000),
    subFrames: z.array(frame).max(512),
  }),
);

const countFrames = (frames: Frame[]): number => frames.reduce((n, f) => n + 1 + countFrames(f.subFrames), 0);

const diagnostic = z
  .strictObject({
    kind: oneOf("diagnosticKind"),
    appVersion: appVersion.optional(),
    osVersion: osVersion.optional(),
    exceptionType: integer.optional(),
    exceptionCode: integer.optional(),
    signal: integer.optional(),
    terminationReason: oneOf("terminationReason").optional(),
    objcExceptionName: oneOf("objcExceptionName").optional(),
    objcExceptionClass: oneOf("objcExceptionClass").optional(),
    hangDuration: oneOf("hangDuration").optional(),
    callStacks: z.array(z.strictObject({ threadAttributed: z.boolean(), frames: z.array(frame) })).max(64),
  })
  .refine((d) => countFrames(d.callStacks.flatMap((s) => s.frames)) <= 512, "too many frames");

const usage = z.strictObject({
  counts: every("feature", bucket),
  portForwardsStarted: every("portForwardKind", bucket),
  connectionOutcome: every("connectionOutcome", bucket),
  authMethodUsed: every("authMethod", z.boolean()),
  keyTypes: every("keyType", z.boolean()),
  savedHosts: bucket,
  identities: bucket,
  iCloudSyncEnabled: z.boolean(),
  customTheme: z.boolean(),
  redactionMode: oneOf("redactionMode"),
  activeDaysLast28: bucket,
});

const detail = z.strictObject({
  connectLatency: every("latencyBucket", bucket),
  remoteOSFamily: every("remoteOSFamily", bucket),
  metrics: z
    .strictObject({
      launchTime: numberIn("millisecondSteps").optional(),
      hangTime: numberIn("millisecondSteps").optional(),
      peakMemory: numberIn("megabyteSteps").optional(),
      cpuTime: numberIn("secondSteps").optional(),
      diskWrites: numberIn("megabyteSteps").optional(),
    })
    .optional(),
});

export const report = z
  .strictObject({
    schema: z.literal(1),
    nonce: z.guid(),
    level: z.union([z.literal(1), z.literal(2), z.literal(3)]),
    appVersion,
    channel: oneOf("channel").refine((c) => c !== "debug", "a debug build"),
    platform: oneOf("platform"),
    osVersion,
    deviceClass: oneOf("deviceClass"),
    language: oneOf("language"),
    regionGroup: oneOf("regionGroup"),
    diagnostics: z.array(diagnostic).max(20),
    usage: usage.optional(),
    detail: detail.optional(),
  })
  .refine((r) => (r.usage === undefined || r.level >= 2) && (r.detail === undefined || r.level === 3), "more than the level allows");

export type Report = z.infer<typeof report>;
export type Diagnostic = z.infer<typeof diagnostic>;

export const batch = z.strictObject({ reports: z.array(z.unknown()).min(1).max(10) });
