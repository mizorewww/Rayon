// The deploy configuration `cf deploy` reads. wrangler.toml mirrors it for
// `wrangler dev` and the tests; keep the two in step.
import { bindings, defineConfig, triggers } from "cf/config";

export default defineConfig({
  worker: {
    name: "rayon-telemetry",
    compatibilityDate: "2026-11-01",
    entrypoint: "./src/index.ts",
    // Only the custom domain: workers.dev is unreliable from mainland China
    // and would give the endpoint a second address.
    domains: ["telemetry.kfcv50.today"],
    workersDev: false,
    previewUrls: false,
    // Nothing about a request is kept anywhere but the aggregates.
    logpush: false,
    observability: {
      enabled: false,
      logs: { enabled: false, invocationLogs: false, persist: false },
      traces: { enabled: false, persist: false },
    },
    triggers: [triggers.scheduled({ schedule: "17 3 * * *" })],
    env: {
      DB: bindings.d1({ id: "90d72dcf-b4c1-4bb8-8322-5ee7ae53757a", name: "rayon-telemetry" }),
      READ_SECRET: bindings.secret(),
    },
  },
});
