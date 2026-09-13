function normalizeYfmTableBlock(lines) {
    const rows = lines.map((line) => {
        const match = line.match(/^\s*\|\|(.*)\|\|\s*$/);
        if (!match) return null;
        return match[1].split("|").map((cell) => cell.trim());
    });
    if (rows.length === 0 || rows.some((row) => !row)) return null;
    const width = Math.max(...rows.map((row) => row.length));
    if (width === 0) return null;
    const normalizedRows = rows.map((row) => [...row, ...Array(Math.max(0, width - row.length)).fill("")]);
    const markdownRow = (row) => `| ${row.map((cell) => cell.replace(/\|/g, "\\|")).join(" | ")} |`;
    return [
        markdownRow(normalizedRows[0]),
        markdownRow(Array(width).fill("---")),
        ...normalizedRows.slice(1).map(markdownRow)
    ];
}

function normalizeYfmTables(value) {
    const lines = value.split("\n");
    const result = [];
    for (let index = 0; index < lines.length; index += 1) {
        if (lines[index].trim() !== "#|") {
            result.push(lines[index]);
            continue;
        }
        const endIndex = lines.findIndex((line, candidate) => candidate > index && line.trim() === "|#");
        if (endIndex < 0) {
            result.push(lines[index]);
            continue;
        }
        const table = normalizeYfmTableBlock(lines.slice(index + 1, endIndex));
        if (!table) {
            result.push(...lines.slice(index, endIndex + 1));
        } else {
            result.push(...table);
        }
        index = endIndex;
    }
    return result.join("\n");
}

function normalizeTrackerProse(value) {
    return normalizeYfmTables(value)
        .replace(/^(#{1,6}\s+.*?)\s+\{#[A-Za-z0-9_-]+\}\s*$/gm, "$1")
        .replace(
            /!\[([^\]]*)\]\(\s*(https?:\/\/[^\s)]+)\s*=\s*(\d{1,5})x(\d{1,5})\s*\)/gi,
            (_match, alt, url, width, height) => `![${alt}](${url} "yfm-size:${width}x${height}")`
        );
}

export function normalizeTrackerMarkdown(value) {
    const lines = String(value || "").replace(/\r\n?/g, "\n").split("\n");
    const output = [];
    let prose = [];
    let fence = null;

    const flushProse = () => {
        if (prose.length === 0) return;
        output.push(normalizeTrackerProse(prose.join("\n")));
        prose = [];
    };

    lines.forEach((line) => {
        const marker = line.match(/^\s*(`{3,}|~{3,})/)?.[1] || null;
        if (!fence && marker) {
            flushProse();
            fence = marker[0];
            output.push(line);
            return;
        }
        if (fence) {
            output.push(line);
            if (marker?.[0] === fence) fence = null;
            return;
        }
        prose.push(line);
    });
    flushProse();
    return output.join("\n");
}

function cutTitle(rawTitle) {
    let title = String(rawTitle || "").trim().replace(/^title\s*=\s*/i, "").trim();
    if ((title.startsWith('"') && title.endsWith('"')) || (title.startsWith("'") && title.endsWith("'"))) {
        title = title.slice(1, -1).trim();
    }
    return title || "Details";
}

export function parseTrackerMarkdown(value) {
    const lines = String(value || "").split("\n");
    const root = [];
    const stack = [root];
    let fence = null;

    const appendMarkdown = (line, includeNewline) => {
        const target = stack[stack.length - 1];
        const text = `${line}${includeNewline ? "\n" : ""}`;
        const previous = target[target.length - 1];
        if (previous?.type === "markdown") previous.content += text;
        else target.push({ type: "markdown", content: text });
    };

    lines.forEach((line, index) => {
        const includeNewline = index < lines.length - 1;
        const marker = line.match(/^\s*(`{3,}|~{3,})/)?.[1] || null;
        if (!fence && marker) {
            fence = marker[0];
            appendMarkdown(line, includeNewline);
            return;
        }
        if (fence) {
            appendMarkdown(line, includeNewline);
            if (marker?.[0] === fence) fence = null;
            return;
        }

        const cutStart = line.match(/^\s*\{%\s*cut(?:\s+(.+?))?\s*%\}\s*$/i);
        if (cutStart) {
            const node = { type: "cut", title: cutTitle(cutStart[1]), children: [] };
            stack[stack.length - 1].push(node);
            stack.push(node.children);
            return;
        }
        if (/^\s*\{%\s*endcut\s*%\}\s*$/i.test(line)) {
            if (stack.length > 1) stack.pop();
            else appendMarkdown(line, includeNewline);
            return;
        }
        appendMarkdown(line, includeNewline);
    });

    return root.filter((node) => node.type !== "markdown" || node.content.length > 0);
}
