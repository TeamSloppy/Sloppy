type DirectoryPicker = () => Promise<{ path?: string | null } | null | undefined>;

export type DroppedPluginDirectoryResult = {
  path: string;
  name: string;
  status: "ready" | "needs_picker" | "empty";
};

export function fileUriToPath(value: string) {
  try {
    const url = new URL(value);
    if (url.protocol !== "file:") {
      return "";
    }
    let pathname = decodeURIComponent(url.pathname || "");
    if (/^\/[A-Za-z]:/.test(pathname)) {
      pathname = pathname.slice(1);
    }
    return pathname;
  } catch {
    return "";
  }
}

export function pathBasename(value: string) {
  return String(value || "")
    .replace(/\/+$/, "")
    .split(/[\\/]/)
    .filter(Boolean)
    .pop() || "plugin";
}

export function droppedDirectoryPayload(dataTransfer: DataTransfer | any) {
  const uriList = dataTransfer.getData?.("text/uri-list") || "";
  const fileUri = String(uriList || "")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .find((line) => line && !line.startsWith("#") && line.startsWith("file://"));
  if (fileUri) {
    const path = fileUriToPath(fileUri);
    if (path) {
      return { path, name: pathBasename(path), hasDirectory: true };
    }
  }

  let directoryName = "";
  for (const item of Array.from(dataTransfer.items || []) as DataTransferItem[]) {
    const entry = (item as any).webkitGetAsEntry?.();
    if (entry?.isDirectory) {
      directoryName = entry.name || directoryName;
      const file = item.getAsFile?.();
      const filePath = (file as any)?.path || "";
      if (filePath) {
        return { path: filePath, name: entry.name || pathBasename(filePath), hasDirectory: true };
      }
    }
  }

  for (const file of Array.from(dataTransfer.files || []) as File[]) {
    const filePath = (file as any)?.path || "";
    if (filePath) {
      return { path: filePath, name: file.name || pathBasename(filePath), hasDirectory: true };
    }
  }

  return { path: "", name: directoryName, hasDirectory: Boolean(directoryName) };
}

export async function resolveDroppedPluginDirectory(
  dataTransfer: DataTransfer | any,
  selectDirectory?: DirectoryPicker
): Promise<DroppedPluginDirectoryResult> {
  const payload = droppedDirectoryPayload(dataTransfer);
  if (payload.path) {
    return {
      path: payload.path,
      name: payload.name || pathBasename(payload.path),
      status: "ready"
    };
  }
  if (!payload.hasDirectory) {
    return { path: "", name: "", status: "empty" };
  }

  const selected = await selectDirectory?.();
  const selectedPath = typeof selected?.path === "string" ? selected.path : "";
  if (!selectedPath) {
    return { path: "", name: payload.name, status: "needs_picker" };
  }
  return {
    path: selectedPath,
    name: payload.name || pathBasename(selectedPath),
    status: "ready"
  };
}
