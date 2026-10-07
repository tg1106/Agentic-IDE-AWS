import Editor, { type OnMount } from '@monaco-editor/react';
import type * as Monaco from 'monaco-editor';
import { useEffect, useRef } from 'react';
import type { Language } from '../types';
import { MONACO_LANG } from '../types';

interface Props {
  value: string;
  language: Language;
  onChange: (value: string) => void;
  onSave: () => void;
  onRun: () => void;
  /** Called with the editor instance once mounted, so the parent can call executeEdits */
  onMount: (editor: Monaco.editor.IStandaloneCodeEditor) => void;
}

export default function EditorPane({ value, language, onChange, onSave, onRun, onMount }: Props) {
  const editorRef = useRef<Monaco.editor.IStandaloneCodeEditor | null>(null);

  // Sync language when it changes externally (e.g. opening a .cpp file while Python is selected)
  useEffect(() => {
    const model = editorRef.current?.getModel();
    if (model) {
      // monaco is available globally after the editor mounts
      (window as unknown as { monaco?: typeof Monaco }).monaco
        ?.editor.setModelLanguage(model, MONACO_LANG[language]);
    }
  }, [language]);

  const handleMount: OnMount = (editor, monaco) => {
    editorRef.current = editor;

    // Expose monaco globally so the language-sync effect above can reach it
    (window as unknown as { monaco: typeof Monaco }).monaco = monaco;

    // Keyboard shortcuts
    editor.addCommand(
      monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS,
      () => onSave(),
    );
    editor.addCommand(
      monaco.KeyMod.CtrlCmd | monaco.KeyCode.Enter,
      () => onRun(),
    );

    onMount(editor);
  };

  return (
    <div className="editor-pane">
      <Editor
        height="100%"
        language={MONACO_LANG[language]}
        value={value}
        theme="vs-dark"
        options={{
          fontSize: 14,
          minimap: { enabled: false },
          scrollBeyondLastLine: false,
          automaticLayout: true,
          tabSize: 4,
        }}
        onChange={v => onChange(v ?? '')}
        onMount={handleMount}
      />
    </div>
  );
}
