import { describe, expect, it } from "vitest";
import { failureExitCode } from "../../scripts/syntax-parity-process.mjs";

describe("syntax parity runner", () => {
  it("fails closed when a successful process does not produce its report", () => {
    expect(failureExitCode({ status: 0 })).toBe(2);
    expect(failureExitCode({ status: null })).toBe(2);
  });

  it("preserves a non-zero child process exit code", () => {
    expect(failureExitCode({ status: 1 })).toBe(1);
    expect(failureExitCode({ status: 7 })).toBe(7);
  });
});
