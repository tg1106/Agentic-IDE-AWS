import type { Language } from '../types';
import { LANGUAGES } from '../types';

interface Props {
  language: Language;
  onLanguageChange: (l: Language) => void;
  dirty: boolean;
  running: boolean;
  onNew: () => void;
  onSave: () => void;
  onRun: () => void;
}

export default function Header({
  language,
  onLanguageChange,
  dirty,
  running,
  onNew,
  onSave,
  onRun,
}: Props) {
  return (
    <header className="app-header">
      <span className="logo">Agentic IDE</span>

      {dirty && (
        <span className="dirty-dot" title="Unsaved changes" aria-label="Unsaved changes">
          ●
        </span>
      )}

      <select
        className="lang-select"
        aria-label="Language"
        value={language}
        onChange={e => onLanguageChange(e.target.value as Language)}
      >
        {LANGUAGES.map(l => (
          <option key={l.value} value={l.value}>{l.label}</option>
        ))}
      </select>

      <button className="btn secondary" onClick={onNew}>
        New file
      </button>

      <button className="btn secondary" onClick={onSave} title="Ctrl/Cmd+S">
        Save
      </button>

      <button
        className="btn go"
        onClick={onRun}
        disabled={running}
        title="Ctrl/Cmd+Enter"
      >
        {running ? 'Running…' : 'Run ▶'}
      </button>
    </header>
  );
}
