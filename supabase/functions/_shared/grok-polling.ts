export interface GrokPollHttpFailureInput {
  statusCode: number;
  ageMinutes: number;
  timeoutMinutes: number;
}

export function classifyGrokPollHttpFailure(
  input: GrokPollHttpFailureInput,
): string | null {
  const { statusCode, ageMinutes, timeoutMinutes } = input;

  // Remote provider no longer recognizes this request id, so the generation can never recover.
  if (statusCode === 404) {
    return "This video request is no longer available. Please start a new one.";
  }

  // Other HTTP failures can be transient, so only fail them once the job is stale.
  if (ageMinutes > timeoutMinutes) {
    return `We couldn’t retrieve your video (connection issue, error ${statusCode}). Please try again.`;
  }

  return null;
}
