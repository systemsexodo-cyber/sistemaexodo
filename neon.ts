import { defineConfig } from "@neon/config/v1";

export default defineConfig({
  // Declare your Neon services here
  auth: true,
  dataApi: true,
  // ⚠️ AI Gateway NÃO atende requisições no plano Free (org-tiny-feather-41583558).
  // Reative esta linha depois de fazer upgrade para um plano pago:
  // https://console.neon.tech/app/org-tiny-feather-41583558/billing
  // aiGateway: true,
  functions: {
    hello: { name: "Hello World", source: "./hello.ts" },
  },
  buckets: {
    // "private" is the default; use "public_read" for anonymous reads.
    // `atualizacoes` e `imagens` precisam ser públicas: o app guarda a URL
    // (`getPublicUrl`) do pacote de atualização e das imagens em outro PC.
    assets: { access: "private" },
    imagens: { access: "public_read" },
    atualizacoes: { access: "public_read" },
    backups: { access: "private" },
    dumps: { access: "private" },
    xmls: { access: "private" },
  },
  // Branch policy: per-branch tuning
  branch: (branch) => {
    if (branch.isDefault) {
      // Default branch: no overrides, uses project defaults
      return {};
    }
    if (!branch.exists) {
      // New non-default branches: auto-expire
      // Run `neon checkout <name>` to create a new branch with these settings
      return { ttl: "7d" };
    }
    // Existing branch: no changes
    return {};
  },
});
