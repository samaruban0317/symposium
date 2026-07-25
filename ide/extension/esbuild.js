// esbuild bundler for the Symposium ML extension.
// Bundles src/extension.ts -> dist/extension.js (CommonJS, node/vscode externals).
const esbuild = require("esbuild");

const production = process.argv.includes("--production");
const watch = process.argv.includes("--watch");

/** @type {import('esbuild').BuildOptions} */
const options = {
  entryPoints: ["src/extension.ts"],
  bundle: true,
  format: "cjs",
  platform: "node",
  target: "node18",
  outfile: "dist/extension.js",
  // vscode is provided by the host at runtime and must never be bundled.
  external: ["vscode"],
  sourcemap: !production,
  minify: production,
  logLevel: "info"
};

async function main() {
  if (watch) {
    const ctx = await esbuild.context(options);
    await ctx.watch();
    console.log("[symposium] esbuild watching...");
  } else {
    await esbuild.build(options);
    console.log("[symposium] esbuild build complete.");
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
