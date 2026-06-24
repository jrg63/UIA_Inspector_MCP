// esbuild bundler config for VS Code extension
// Two entry points:
//   extension.ts → out/extension.js  (extension host, vscode external)
//   mcpBridge.ts  → out/mcpBridge.js  (child process, node builtins only)

import * as esbuild from "esbuild";

const isWatch = process.argv.includes("--watch");

/** @type {esbuild.BuildOptions} */
const extensionConfig = {
    entryPoints: ["src/extension.ts"],
    bundle: true,
    outfile: "out/extension.js",
    external: ["vscode"],
    format: "cjs",
    platform: "node",
    target: "node20",
    sourcemap: true,
    minify: false,
    keepNames: true,
    logLevel: "info",
    metafile: true,
};

/** @type {esbuild.BuildOptions} */
const bridgeConfig = {
    entryPoints: ["src/mcpBridge.ts"],
    bundle: true,
    outfile: "out/mcpBridge.js",
    format: "cjs",
    platform: "node",
    target: "node20",
    sourcemap: true,
    minify: false,
    keepNames: true,
    logLevel: "info",
};

if (isWatch) {
    const extCtx = await esbuild.context(extensionConfig);
    const brCtx = await esbuild.context(bridgeConfig);
    await Promise.all([extCtx.watch(), brCtx.watch()]);
    console.log("[esbuild] Watching for changes...");
} else {
    await Promise.all([
        esbuild.build(extensionConfig),
        esbuild.build(bridgeConfig),
    ]);
    console.log("[esbuild] Build complete.");
}
