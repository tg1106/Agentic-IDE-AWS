import { useEffect, useRef, useState } from 'react';
import { startSolve, type TestCase } from '../api';
import type { Language, LogEntry } from '../types';

interface Props {
  language: Language;
  /** Called when the agent produces a new code block; App patches the editor */
  onAgentCode: (code: string) => void;
}

let _logId = 0;
const nextId = () => ++_logId;

export default function SolvePanel({ language, onAgentCode }: Props) {
  const [problem, setProblem]   = useState('');
  const [testsRaw, setTestsRaw] = useState('');
  const [log, setLog]           = useState<LogEntry[]>([
    { id: nextId(), text: 'The agent writes code, runs your tests, and fixes failures.', kind: 'dim' },
  ]);
  const [solving, setSolving]   = useState(false);
  const logEndRef               = useRef<HTMLDivElement>(null);
  const stopRef                 = useRef<(() => void) | null>(null);

  // Auto-scroll log
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
    // Validate tests JSON
    let tests: TestCase[];
    try {
      tests = JSON.parse(testsRaw || '[]') as TestCase[];
    } catch {
      addLog('Tests must be valid JSON.', 'bad');
      return;
    }
    if (!problem.trim()) {
      addLog('Paste a problem statement first.', 'bad');
      return;
    }

    clearLog();
    setSolving(true);

    stopRef.current = startSolve(
      problem,
      language,
      tests,
      // onEvent
      (ev) => {
        if (ev.type === 'status') {
          addLog(ev.msg, 'dim');
        } else if (ev.type === 'code') {
          onAgentCode(ev.code);
        } else if (ev.type === 'result') {
          const allPassed = ev.passed === ev.total;
          addLog(`Passed ${ev.passed}/${ev.total} tests`, allPassed ? 'ok' : 'bad');
        } else if (ev.type === 'done') {
          const kind =
            ev.passed === true  ? 'ok'  :
            ev.passed === false ? 'bad' : 'warn';
          addLog(ev.msg, kind);
        }
      },
      // onError
      (msg) => addLog(msg, 'bad'),
      // onDone
      () => setSolving(false),
    );
  }

  function handleStop() {
    stopRef.current?.();
    stopRef.current = null;
    setSolving(false);
    addLog('Solve cancelled.', 'warn');
  }

  return (
    <section className="solve-panel" aria-label="Agent solver">
      <h3 className="panel-title">Solve a problem</h3>

      <textarea
        className="problem-area"
        placeholder="Paste the problem statement here"
        aria-label="Problem statement"
        value={problem}
        onChange={e => setProblem(e.target.value)}
        spellCheck={false}
      />

      <label className="field-label" htmlFor="tests-input">
        Tests as JSON — e.g. {"[{\"input\":\"1 2\\n\",\"expected\":\"3\"}]"}
      </label>
      <textarea
        id="tests-input"
        className="tests-area"
        placeholder='[{"input":"...","expected":"..."}]'
        aria-label="Test cases JSON"
        value={testsRaw}
        onChange={e => setTestsRaw(e.target.value)}
        spellCheck={false}
      />

      <div className="solve-actions">
        {!solving ? (
          <button className="btn go" onClick={handleSolve}>
            Solve with agent
          </button>
        ) : (
          <button className="btn danger" onClick={handleStop}>
            Stop
          </button>
        )}
        <button className="btn secondary" onClick={clearLog} disabled={solving}>
          Clear log
        </button>
      </div>

      <div className="agent-log" role="log" aria-live="polite" aria-label="Agent log">
        {log.map(entry => (
          <div key={entry.id} className={`log-entry ${entry.kind}`}>
            {entry.text}
          </div>
        ))}
        <div ref={logEndRef} />
      </div>
    </section>
  );
}
