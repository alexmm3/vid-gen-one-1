export interface GrokPollHttpFailureInput {
  statusCode: number;
  ageMinutes: number;
  timeoutMinutes: number;
}

export function classifyGrokPollHttpFailure(
  input: GrokPollHttpFailureInput,
): string | null {
  const { statusCode, ageMinutes, timeoutMinutes } = input;

  // xAI no longer recognizes this request id, so the generation can never recover.
  if (statusCode === 404) {
    return "Grok generation request not found";
  }

  // Other HTTP failures can be transient, so only fail them once the job is stale.
  if (ageMinutes > timeoutMinutes) {
    return `Grok polling failed with HTTP ${statusCode} after ${Math.round(ageMinutes)} minutes`;
  }

  return null;
}
