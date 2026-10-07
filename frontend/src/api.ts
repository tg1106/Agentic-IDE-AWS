/**
 * Typed wrappers for every backend endpoint.
 *
 * The FastAPI server uses HTTP Basic Auth on all routes. The browser caches
 * credentials after the first 401 challenge, so we don't need to embed them
 * in the client. For the SSE endpoint we pass `credentials: 'include'` so
 * the browser sends the cached credentials automatically.
 */

export interface RunResult {
  stdout: string;
  stderr: string;
  exit_code: number;
  timed_out: boolean;
}

export interface TestCase {
  input: string;
  expected: string;
}

/** Union of all SSE event shapes emitted by /api/agent/solve */
export type AgentEvent =
  | { type: 'status'; msg: string }
  | { type: 'code'; code: string }
  | { type: 'result'; passed: number; total: number }
  | { type: 'done'; passed: boolean | null; msg: string };

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  const res = await fetch('/api' + path, {
    ...init,
    credentials: 'include',
    headers: {
      ...(init.headers ?? {}),
    },
  });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error((body as { detail?: string }).detail ?? res.statusText);
  }
  return res.json() as Promise<T>;
}

function json(body: unknown): RequestInit {
  return {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  };
}

// ---------------------------------------------------------------------------
// File API
// ---------------------------------------------------------------------------

export const listFiles = (): Promise<string[]> =>
  request<string[]>('/files');

export const readFile = (name: string): Promise<{ content: string }> =>
  request<{ content: string }>('/files/' + encodeURIComponent(name));

export const writeFile = (name: string, content: string): Promise<{ ok: boolean }> =>
  request<{ ok: boolean }>('/files/' + encodeURIComponent(name), {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ content }),
  });

export const deleteFile = (name: string): Promise<{ ok: boolean }> =>
  request<{ ok: boolean }>('/files/' + encodeURIComponent(name), {
    method: 'DELETE',
  });

// ---------------------------------------------------------------------------
// Run endpoint
// ---------------------------------------------------------------------------

export const runCode = (
  language: string,
  code: string,
  stdin: string,
): Promise<RunResult> =>
  request<RunResult>('/run', json({ language, code, stdin }));

// ---------------------------------------------------------------------------
// Agent / SSE endpoint
// ---------------------------------------------------------------------------

/**
 * Opens an SSE stream for /api/agent/solve and calls `onEvent` for each
 * parsed event. Returns a cleanup function that aborts the stream.
 */
export function startSolve(
  problem: string,
  language: string,
  tests: TestCase[],
  onEvent: (ev: AgentEvent) => void,
  onError: (msg: string) => void,
  onDone: () => void,
): () => void {
  const controller = new AbortController();

  (async () => {
    let res: Response;
    try {
      res = await fetch('/api/agent/solve', {
        ...json({ problem, language, tests }),
        credentials: 'include',
        signal: controller.signal,
      });
    } catch (e: unknown) {
      if ((e as { name?: string }).name !== 'AbortError') {
        onError('Network error: ' + String(e));
      }
      onDone();
      return;
    }

    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      onError((body as { detail?: string }).detail ?? res.statusText);
      onDone();
      return;
    }

    const reader = res.body!.getReader();
    const dec = new TextDecoder();
    let buf = '';

    try {
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        buf += dec.decode(value, { stream: true });
        const parts = buf.split('\n\n');
        buf = parts.pop() ?? '';
        for (const part of parts) {
          if (part.startsWith('data: ')) {
            try {
              onEvent(JSON.parse(part.slice(6)) as AgentEvent);
            } catch {
              /* malformed chunk — skip */
            }
          }
        }
      }
    } catch (e: unknown) {
      if ((e as { name?: string }).name !== 'AbortError') {
        onError('Stream error: ' + String(e));
      }
    } finally {
      onDone();
    }
  })();

  return () => controller.abort();
}
