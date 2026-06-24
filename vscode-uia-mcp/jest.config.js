/** @type {import('ts-jest').JestConfigWithTsJest} */
module.exports = {
    preset: "ts-jest",
    testEnvironment: "node",
    roots: ["<rootDir>/src"],
    testMatch: ["**/__tests__/**/*.test.ts"],
    moduleFileExtensions: ["ts", "tsx", "js", "jsx", "json", "node"],
    // Only collect coverage from modules that don't depend on vscode APIs.
    // ahkDaemon.ts, mcpServer.ts, and extension.ts require the VS Code
    // runtime and are tested via integration tests (test_engine.ps1).
    collectCoverageFrom: [
        "src/pathResolver.ts",
        "src/toolDefinitions.ts",
    ],
    coverageThreshold: {
        global: {
            branches: 90,
            functions: 90,
            lines: 90,
            statements: 90,
        },
    },
};
