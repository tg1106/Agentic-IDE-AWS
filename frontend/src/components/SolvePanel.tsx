import { useEffect, useRef, useState } from 'react';
import { startSolve } from '../api';
import type { Language, LogEntry } from '../types';

interface Props {
  language: Language;
  onAgentCode: (code: string) => void;
}

let _logId = 0;
const nextId = () => ++_logId;

export default function SolvePanel({ language, onAgentCode }: Props) {
  const [problem, setProblem] = useState('');
  const [log, setLog]         = useState<LogEntry[]>([
    { id: nextId(), text: 'Describe what you want to solve. The agent will write, run, and fix the code.', kind: 'dim' },
  ]);
  const [solving, setSolving] = useState(false);
  const logEndRef             = useRef<HTMLDivElement>(null);
  const stopRef               = useRef<(() => void) | null>(null);

  useEffect(() => {
    logEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [log]);

  function addLog(text: string, kind: LogEntry['kind']) {
    setLog(prev => [...prev, { id: nextId(), text, kind }]);
  }

  function clearLog() {
    setLog([]);
  }

  function handleSolve() {
    if (!problem.trim()) {
      addLog('Type a message first.', 'bad');
      return;
    }

    clearLog();
    setSolving(true);

    // Pass empty tests array — agent will write and run code without test validation
    stopRef.current = startSolve(
      problem,
      language,
      [],
      (ev) => {
        if (ev.type === 'status') {
          addLog(ev.msg, 'dim');
        } else if (ev.type === 'code') {
          onAgentCode(ev.code);
          addLog('Code updated in editor.', 'ok');
        } else if (ev.type === 'result') {
          addLog(`Passed ${ev.passed}/${ev.total} tests`, ev.passed === ev.total ? 'ok' : 'bad');
        } else if (ev.type === 'done') {
          const kind = ev.passed === true ? 'ok' : ev.passed === false ? 'bad' : 'warn';
          addLog(ev.msg, kind);
        }
      },
      (msg) => addLog(msg, 'bad'),
      () => setSolving(false),
    );
  }

  function handleStop() {
    stopRef.current?.();
    stopRef.current = null;
    setSolving(false);
    addLog('Cancelled.', 'warn');
  }

  function handleKeyDown(e: React.KeyboardEvent<HTMLTextAreaElement>) {
    // Ctrl+Enter or Cmd+Enter to send
    if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
      e.preventDefault();
      if (!solving) handleSolve();
    }
  }

  return (
    <section className="solve-panel" aria-label="Agent chat">
      <h3 className="panel-title">Ask the agent</h3>

      <div className="agent-log" role="log" aria-live="polite" aria-label="Agent log">
        {log.map(entry => (
          <div key={entry.id} className={`log-entry ${entry.kind}`}>
            {entry.text}
          </div>
        ))}
        <div ref={logEndRef} />
      </div>

      <div className="chat-input-area">
        <textarea
          className="chat-textarea"
          placeholder="Describe a problem or ask the agent to write code… (Ctrl+Enter to send)"
          aria-label="Message to agent"
          value={problem}
          onChange={e => setProblem(e.target.value)}
          onKeyDown={handleKeyDown}
          spellCheck={false}
          disabled={solving}
        />
        <div className="chat-actions">
          {!solving ? (
            <button className="btn go" onClick={handleSolve}>
              Send ▶
            </button>
          ) : (
            <button className="btn danger" onClick={handleStop}>
              Stop
            </button>
          )}
          <button className="btn secondary" onClick={clearLog} disabled={solving}>
            Clear
          </button>
        </div>
      </div>
    </section>
  );
}
