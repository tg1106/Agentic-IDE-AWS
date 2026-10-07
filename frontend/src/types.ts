export type Language = 'python' | 'cpp';

export const LANGUAGES: { value: Language; label: string }[] = [
  { value: 'python', label: 'Python 3' },
  { value: 'cpp',    label: 'C++17'   },
];

export const FILE_EXT: Record<Language, string> = {
  python: '.py',
  cpp:    '.cpp',
};

export const MONACO_LANG: Record<Language, string> = {
  python: 'python',
  cpp:    'cpp',
};

export const CODE_TEMPLATES: Record<Language, string> = {
  python: `import sys\ninput = sys.stdin.readline\n\ndef main():\n    pass\n\nmain()\n`,
  cpp: `#include <bits/stdc++.h>\nusing namespace std;\n\nint main() {\n    ios::sync_with_stdio(false);\n    cin.tie(nullptr);\n\n    return 0;\n}\n`,
};

/** One entry in the agent log panel */
export interface LogEntry {
  id: number;
  text: string;
  kind: 'dim' | 'ok' | 'bad' | 'warn' | 'normal';
}
