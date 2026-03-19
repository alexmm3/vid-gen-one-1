import {
  classifyGrokPollHttpFailure,
} from "./grok-polling.ts";

Deno.test("fails immediately when Grok returns 404", () => {
  const result = classifyGrokPollHttpFailure({
    statusCode: 404,
    ageMinutes: 1,
    timeoutMinutes: 10,
  });

  if (result !== "Grok generation request not found") {
    throw new Error(`Unexpected result: ${result}`);
  }
});

Deno.test("keeps transient HTTP errors processing before timeout", () => {
  const result = classifyGrokPollHttpFailure({
    statusCode: 500,
    ageMinutes: 3,
    timeoutMinutes: 10,
  });

  if (result !== null) {
    throw new Error(`Expected null, got: ${result}`);
  }
});

Deno.test("fails stale HTTP errors after timeout", () => {
  const result = classifyGrokPollHttpFailure({
    statusCode: 500,
    ageMinutes: 12.4,
    timeoutMinutes: 10,
  });

  if (result !== "Grok polling failed with HTTP 500 after 12 minutes") {
    throw new Error(`Unexpected result: ${result}`);
  }
});
