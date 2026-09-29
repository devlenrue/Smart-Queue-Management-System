/** @type {import('ts-jest').JestConfigWithTsJest} */
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  roots: ['<rootDir>/tests'],
  testMatch: ['**/*.test.ts'],
  setupFilesAfterEnv: ['<rootDir>/tests/setup.ts'],
  testTimeout: 30000,
  clearMocks: true,
  collectCoverageFrom: ['src/**/*.ts', '!src/db/cli/**', '!src/server.ts'],
  /**
   * Phase 9 floors. `./src/services/` is a directory key, so Jest applies it
   * to the business-logic layer as a group — that is the ≥ 80 % the roadmap
   * asks for. The glob key underneath it is a per-file floor, so one badly
   * covered service cannot hide behind eleven well covered ones.
   * Files matched by a more specific key are excluded from `global`.
   */
  coverageThreshold: {
    './src/services/': { statements: 95, branches: 80, functions: 95, lines: 97 },
    './src/services/*.ts': { statements: 90, branches: 70, functions: 90, lines: 90 },
    global: { statements: 88, branches: 68, functions: 86, lines: 90 },
  },
  transform: {
    '^.+\\.ts$': ['ts-jest', { tsconfig: { module: 'commonjs', target: 'ES2022', strict: true, esModuleInterop: true, skipLibCheck: true } }],
  },
};
