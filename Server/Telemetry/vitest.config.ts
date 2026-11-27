import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

export default defineConfig(async () => ({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./wrangler.toml" },
      miniflare: {
        bindings: { READ_SECRET: "test-secret", TEST_MIGRATIONS: await readD1Migrations("./migrations") },
      },
    }),
  ],
  test: { setupFiles: ["./test/apply-migrations.ts"] },
}));
