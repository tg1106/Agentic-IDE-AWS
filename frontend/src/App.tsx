import type * as Monaco from 'monaco-editor';
import { useCallback, useRef, useState } from 'react';
import { readFile, runCode, writeFile, type RunResult } from './api';
import EditorPane from './components/EditorPane';
import FilePanel from './components/FilePanel';
import Header from './components/Header';
import IOPane from './components/IOPane';
import SolvePanel from './components/SolvePanel';
import type { Language } from './types';
import { CODE_TEMPLATES, FILE_EXT } from './types';

export default function App() {
  const [language, setLanguage]       = useState<Language>('python');
  const [code, setCode]               = useState(CODE_TEMPLATES.python);
  const [currentFile, setCurrentFile] = useState('');
  const [dirty, setDirty]             = useState(false);
  const [stdin, setStdin]             = useState('');
  const [runResult, setRunResult]     = useState<RunResult | null>(null);
  const [running, setRunning]         = useState(false);

  const editorRef = useRef<Monaco.editor.IStandaloneCodeEditor | null>(null);

  // ── Editor change ──────────────────────────────────────────────────────
  const handleCodeChange = useCallback((val: string) => {
    setCode(val);
    setDirty(true);
  }, []);

  // ── Open file ──────────────────────────────────────────────────────────
  const handleOpen = useCallback(async (name: string) => {
    if (!name) {
      // Reset to blank scratch
      setCurrentFile('');
      setCode(CODE_TEMPLATES[language]);
      setDirty(false);
      return;
    }
    try {
      const { content } = await readFile(name);
      setCurrentFile(name);
      setCode(content);
      setLanguage(name.endsWith('.cpp') ? 'cpp' : 'python');
      setDirty(false);
    } catch (e) {
      alert('Could not open file: ' + String(e));
    }
  }, [language]);

  // ── New file created ───────────────────────────────────────────────────
  const handleCreated = useCallback(async (name: string) => {
    const lang: Language = name.endsWith('.cpp') ? 'cpp' : 'python';
    setCurrentFile(name);
    setLanguage(lang);
    setCode(CODE_TEMPLATES[lang]);
    setDirty(true);
    // Immediately save the template so it appears in the file list
    try {
      await writeFile(name, CODE_TEMPLATES[lang]);
      setDirty(false);
    } catch (e) {
      alert('Save failed: ' + String(e));
    }
  }, []);

  // ── Language change ────────────────────────────────────────────────────
  const handleLanguageChange = useCallback((lang: Language) => {
    setLanguage(lang);
    // Only replace code with template when there's no open file
    if (!currentFile) {
      setCode(CODE_TEMPLATES[lang]);
      setDirty(false);
    }
  }, [currentFile]);

  // ── Save ───────────────────────────────────────────────────────────────
  const handleSave = useCallback(async () => {
    const name = currentFile || 'scratch' + FILE_EXT[language];
    try {
      await writeFile(name, code);
      setCurrentFile(name);
      setDirty(false);
    } catch (e) {
      alert('Save failed: ' + String(e));
    }
  }, [currentFile, language, code]);

  // ── Run ────────────────────────────────────────────────────────────────
  const handleRun = useCallback(async () => {
    setRunning(true);
    setRunResult(null);
    try {
      const result = await runCode(language, code, stdin);
      setRunResult(result);
    } catch (e) {
      setRunResult({
        stdout: '',
        stderr: String(e),
        exit_code: 1,
        timed_out: false,
      });
    } finally {
      setRunning(false);
    }
  }, [language, code, stdin]);

  // ── Agent code injection (uses executeEdits to preserve undo history) ──
  const handleAgentCode = useCallback((newCode: string) => {
    const editor = editorRef.current;
    if (!editor) {
      setCode(newCode);
      setDirty(true);
      return;
    }
    editor.executeEdits('agent', [{
      range: editor.getModel()!.getFullModelRange(),
      text: newCode,
    }]);
    setCode(newCode);
    setDirty(true);
  }, []);

  return (
    <div className="app-grid">
      <Header
        language={language}
        onLanguageChange={handleLanguageChange}
        dirty={dirty}
        running={running}
        onNew={() => {/* open the file panel form — triggered via FilePanel's own button */}}
        onSave={handleSave}
        onRun={handleRun}
      />

      <FilePanel
        currentFile={currentFile}
        language={language}
        dirty={dirty}
        onOpen={handleOpen}
        onCreated={handleCreated}
      />

      <div className="editor-wrapper">
        <EditorPane
          value={code}
          language={language}
          onChange={handleCodeChange}
          onSave={handleSave}
          onRun={handleRun}
          onMount={editor => { editorRef.current = editor; }}
        />
        <IOPane
          stdin={stdin}
          onStdinChange={setStdin}
          result={runResult}
          running={running}
        />
      </div>

      <SolvePanel
        language={language}
        onAgentCode={handleAgentCode}
      />
    </div>
  );
}
