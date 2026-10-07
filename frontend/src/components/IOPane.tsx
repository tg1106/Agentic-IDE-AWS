import type { RunResult } from '../api';

interface Props {
  stdin: string;
  onStdinChange: (v: string) => void;
  result: RunResult | null;
  running: boolean;
}

export default function IOPane({ stdin, onStdinChange, result, running }: Props) {
  return (
    <div className="io-pane">
      <textarea
        className="stdin-area"
        placeholder="stdin — program input"
        aria-label="Standard input"
        value={stdin}
        onChange={e => onStdinChange(e.target.value)}
        spellCheck={false}
      />

      <div className="output-area" role="log" aria-live="polite" aria-label="Program output">
        {running && <span className="dim">Running…</span>}

        {!running && result === null && (
          <span className="dim">Output appears here.</span>
        )}

        {!running && result !== null && (
          <>
            {result.stdout && <span className="out-stdout">{result.stdout}</span>}
            {result.stderr && <span className="out-stderr">{'\n' + result.stderr}</span>}
            <div className={result.exit_code === 0 ? 'exit-ok' : 'exit-bad'}>
              {result.timed_out ? 'Time limit exceeded' : `Exit code ${result.exit_code}`}
            </div>
          </>
        )}
      </div>
    </div>
  );
}
