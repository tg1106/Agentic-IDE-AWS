import { useEffect, useRef, useState } from 'react';
import { deleteFile, listFiles } from '../api';
import type { Language } from '../types';
import { FILE_EXT } from '../types';

interface Props {
  currentFile: string;
  language: Language;
  dirty: boolean;
  onOpen: (name: string) => void;
  onCreated: (name: string) => void;
}

export default function FilePanel({ currentFile, language, dirty, onOpen, onCreated }: Props) {
  const [files, setFiles] = useState<string[]>([]);
  const [showForm, setShowForm] = useState(false);
  const [newName, setNewName] = useState('');
  const inputRef = useRef<HTMLInputElement>(null);

  async function refresh() {
    try {
      setFiles(await listFiles());
    } catch {
      /* server may not be ready yet */
    }
  }

  useEffect(() => { refresh(); }, [currentFile]);

  useEffect(() => {
    if (showForm) inputRef.current?.focus();
  }, [showForm]);

  function handleOpen(name: string) {
    if (dirty && !confirm('You have unsaved changes. Open another file anyway?')) return;
    onOpen(name);
  }

  async function handleDelete(e: React.MouseEvent, name: string) {
    e.stopPropagation();
    if (!confirm(`Delete ${name}? This cannot be undone.`)) return;
    try {
      await deleteFile(name);
      await refresh();
      // If we deleted the currently open file, reset is handled by the parent via onOpen('')
      if (name === currentFile) onOpen('');
    } catch (err) {
      alert('Delete failed: ' + String(err));
    }
  }

  function handleNewKeyDown(e: React.KeyboardEvent) {
    if (e.key === 'Enter')  commitNew();
    if (e.key === 'Escape') cancelNew();
  }

  function commitNew() {
    const stem = newName.trim().replace(/\.(cpp|py)$/, '');
    if (!stem) return;
    const fullName = stem + FILE_EXT[language];
    setShowForm(false);
    setNewName('');
    if (dirty && !confirm('You have unsaved changes. Create a new file anyway?')) return;
    onCreated(fullName);
  }

  function cancelNew() {
    setShowForm(false);
    setNewName('');
  }

  return (
    <aside className="file-panel">
      <h3 className="panel-title">Files</h3>

      <button
        className="new-file-btn"
        onClick={() => setShowForm(true)}
        title="New file"
      >
        + New file
      </button>

      {showForm && (
        <div className="new-form" role="group" aria-label="New file name">
          <input
            ref={inputRef}
            className="new-input"
            type="text"
            maxLength={60}
            placeholder="filename (no ext)"
            aria-label="New file name"
            autoComplete="off"
            spellCheck={false}
            value={newName}
            onChange={e => setNewName(e.target.value)}
            onKeyDown={handleNewKeyDown}
          />
          <button className="icon-btn ok-btn"  onClick={commitNew} title="Create" aria-label="Create file">✓</button>
          <button className="icon-btn"          onClick={cancelNew} title="Cancel" aria-label="Cancel">✕</button>
        </div>
      )}

      <ul className="file-list" role="listbox" aria-label="Workspace files">
        {files.length === 0 && (
          <li className="file-item empty">No files yet — save one.</li>
        )}
        {files.map(name => (
          <li
            key={name}
            role="option"
            aria-selected={name === currentFile}
            className={'file-item' + (name === currentFile ? ' active' : '')}
            tabIndex={0}
            onClick={() => handleOpen(name)}
            onKeyDown={e => e.key === 'Enter' && handleOpen(name)}
          >
            <span className="fname">{name}</span>
            <button
              className="del-btn"
              title={`Delete ${name}`}
              aria-label={`Delete ${name}`}
              onClick={e => handleDelete(e, name)}
            >
              ✕
            </button>
          </li>
        ))}
      </ul>
    </aside>
  );
}
