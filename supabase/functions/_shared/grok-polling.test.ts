import {
  classifyGrokPollHttpFailure,
} from "./grok-polling.ts";

Deno.test("fails immediately when Grok returns 404", () => {
  const result = classifyGrokPollHttpFailure({
    statusCode: 404,
    ageMinutes: 1,
    timeoutMinutes: 10,
  });

  if (result !== "This video request is no longer available. Please start a new one.") {
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

  if (result !== "We couldn’t retrieve your video (connection issue, error 500). Please try again.") {
    throw new Error(`Unexpected result: ${result}`);
  }
});
