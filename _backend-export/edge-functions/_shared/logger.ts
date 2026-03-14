// Structured logging utility for edge functions

export type LogLevel = 'debug' | 'info' | 'warn' | 'error';

export interface LogEntry {
  timestamp: string;
  level: LogLevel;
  event: string;
  request_id?: string;
  generation_id?: string;
  message?: string;
  duration_ms?: number;
  retry_attempt?: number;
  api_response?: unknown;
  error?: {
    message: string;
    code?: string;
    stack?: string;
  };
  metadata?: Record<string, unknown>;
}

export interface LogContext {
  request_id: string;
  generation_id?: string;
  function_name: string;
}

/**
 * Generate a unique request ID for correlation
 */
export function generateRequestId(): string {
  return `req_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
}

/**
 * Create a structured log entry
 */
export function createLogEntry(
  level: LogLevel,
  event: string,
  context: Partial<LogContext>,
  details?: Partial<Omit<LogEntry, 'timestamp' | 'level' | 'event'>>
): LogEntry {
  return {
    timestamp: new Date().toISOString(),
    level,
    event,
    request_id: context.request_id,
    generation_id: context.generation_id,
    ...details,
  };
}

/**
 * Logger class for consistent structured logging
 */
export class Logger {
  private context: LogContext;
  private logs: LogEntry[] = [];

  constructor(functionName: string, requestId?: string) {
    this.context = {
      function_name: functionName,
      request_id: requestId || generateRequestId(),
    };
  }

  setGenerationId(id: string) {
    this.context.generation_id = id;
  }

  getRequestId(): string {
    return this.context.request_id;
  }

  getLogs(): LogEntry[] {
    return this.logs;
  }

  private log(level: LogLevel, event: string, details?: Partial<Omit<LogEntry, 'timestamp' | 'level' | 'event'>>) {
    const entry = createLogEntry(level, event, this.context, details);
    this.logs.push(entry);

    // Also output to console for Supabase logs
    const logMethod = level === 'error' ? console.error : 
                      level === 'warn' ? console.warn : 
                      level === 'debug' ? console.debug : console.info;
    
    logMethod(JSON.stringify(entry));
    return entry;
  }

  debug(event: string, details?: Partial<Omit<LogEntry, 'timestamp' | 'level' | 'event'>>) {
    return this.log('debug', event, details);
  }

  info(event: string, details?: Partial<Omit<LogEntry, 'timestamp' | 'level' | 'event'>>) {
    return this.log('info', event, details);
  }

  warn(event: string, details?: Partial<Omit<LogEntry, 'timestamp' | 'level' | 'event'>>) {
    return this.log('warn', event, details);
  }

  error(event: string, error: Error | string, details?: Partial<Omit<LogEntry, 'timestamp' | 'level' | 'event'>>) {
    const errorObj = error instanceof Error 
      ? { message: error.message, stack: error.stack }
      : { message: error };
    
    return this.log('error', event, { ...details, error: errorObj });
  }
}

/**
 * Retry with exponential backoff
 */
export interface RetryConfig {
  maxRetries: number;
  initialDelayMs: number;
  maxDelayMs: number;
  backoffMultiplier: number;
}

export const DEFAULT_RETRY_CONFIG: RetryConfig = {
  maxRetries: 3,
  initialDelayMs: 5000,
  maxDelayMs: 60000,
  backoffMultiplier: 2,
};

export async function withRetry<T>(
  fn: () => Promise<T>,
  logger: Logger,
  config: Partial<RetryConfig> = {}
): Promise<{ result: T; attempts: number } | { error: Error; attempts: number }> {
  const { maxRetries, initialDelayMs, maxDelayMs, backoffMultiplier } = {
    ...DEFAULT_RETRY_CONFIG,
    ...config,
  };

  let lastError: Error | null = null;
  let delay = initialDelayMs;

  for (let attempt = 1; attempt <= maxRetries + 1; attempt++) {
    try {
      logger.info('retry.attempt', { retry_attempt: attempt, metadata: { max_retries: maxRetries } });
      
      const startTime = Date.now();
      const result = await fn();
      const duration = Date.now() - startTime;
      
      logger.info('retry.success', { retry_attempt: attempt, duration_ms: duration });
      return { result, attempts: attempt };
    } catch (error) {
      lastError = error instanceof Error ? error : new Error(String(error));
      
      logger.warn('retry.failed', {
        retry_attempt: attempt,
        error: { message: lastError.message },
        metadata: { will_retry: attempt <= maxRetries, next_delay_ms: delay },
      });

      if (attempt <= maxRetries) {
        await new Promise(resolve => setTimeout(resolve, delay));
        delay = Math.min(delay * backoffMultiplier, maxDelayMs);
      }
    }
  }

  logger.error('retry.exhausted', lastError!, { metadata: { total_attempts: maxRetries + 1 } });
  return { error: lastError!, attempts: maxRetries + 1 };
}

/**
 * Helper to extract output URL from various API response formats
 */
export function extractOutputUrl(result: Record<string, unknown>): string | null {
  // Check for direct output array with actual URLs (not empty)
  if (result.output && Array.isArray(result.output) && result.output.length > 0) {
    const firstOutput = result.output[0];
    if (typeof firstOutput === 'string' && firstOutput.startsWith('http')) {
      return firstOutput;
    }
  }
  
  // Check for direct output string
  if (result.output && typeof result.output === 'string' && (result.output as string).startsWith('http')) {
    return result.output as string;
  }
  
  // Check future_links (where completed videos will eventually be available)
  if (result.future_links && Array.isArray(result.future_links) && result.future_links.length > 0) {
    return result.future_links[0] as string;
  }
  
  return null;
}
