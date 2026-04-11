import { DiffFile } from "@git-diff-view/file";

export type GitDiffFileSection = {
  displayPath: string;
  patchText: string;
};

/** Split a multi-file `git diff` into one patch string per file. */
export function splitUnifiedGitDiff(raw: string): GitDiffFileSection[] {
  const text = raw.replace(/\r\n/g, "\n");
  const t = text.trim();
  if (!t) {
    return [];
  }

  if (!t.includes("diff --git ")) {
    return [{ displayPath: extractPathFromPatchFallback(t), patchText: t }];
  }

  const chunks = t.split(/\n(?=diff --git )/).map((c) => c.trim()).filter(Boolean);
  return chunks.map((patchText) => ({
    displayPath: extractDisplayPathFromChunk(patchText),
    patchText
  }));
}

function extractDisplayPathFromChunk(patch: string): string {
  const first = patch.split("\n")[0] ?? "";
  const unquoted = first.match(/^diff --git a\/(.+?) b\/(.+)$/);
  if (unquoted) {
    return unquoted[2].trim();
  }
  const quoted = first.match(/^diff --git "?a\/(.+?)"?\s+"?b\/(.+?)"?$/);
  if (quoted) {
    return quoted[2].trim();
  }
  return extractPathFromPatchFallback(patch);
}

function extractPathFromPatchFallback(patch: string): string {
  const plus = patch.match(/^\+\+\+ [ab]\/(.+)$/m);
  if (plus) {
    return plus[1].trim();
  }
  const git = patch.match(/^diff --git (.+)$/m);
  return git ? git[1].trim() : "patch";
}

export function highlighterLangForPath(path: string): string {
  const base = path.includes("/") ? path.slice(path.lastIndexOf("/") + 1) : path;
  const dot = base.lastIndexOf(".");
  const ext = dot >= 0 ? base.slice(dot + 1).toLowerCase() : "";
  const map: Record<string, string> = {
    ts: "typescript",
    tsx: "tsx",
    js: "javascript",
    jsx: "javascript",
    mjs: "javascript",
    cjs: "javascript",
    json: "json",
    swift: "swift",
    md: "markdown",
    css: "css",
    scss: "scss",
    html: "html",
    yml: "yaml",
    yaml: "yaml",
    rs: "rust",
    py: "python",
    go: "go"
  };
  return map[ext] ?? "txt";
}

export function createDiffFileFromPatch(displayPath: string, patchText: string): DiffFile {
  const lang = highlighterLangForPath(displayPath);
  const file = new DiffFile(displayPath, "", displayPath, "", [patchText], lang, lang);
  file.initTheme("dark");
  file.init();
  file.buildSplitDiffLines();
  file.buildUnifiedDiffLines();
  return file;
}
