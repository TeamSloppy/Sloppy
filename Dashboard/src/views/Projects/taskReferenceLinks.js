function escapeRegExp(value) {
    return String(value || "").replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export function taskByReference(project, reference) {
    const needle = String(reference || "").replace(/^#+/, "").trim().toLowerCase();
    if (!needle) return null;
    return (project.tasks || []).find((task) => String(task.id || "").trim().toLowerCase() === needle) || null;
}

export function linkifyTaskReferences(markdown, project) {
    const taskIds = (project.tasks || [])
        .map((task) => String(task.id || "").trim())
        .filter(Boolean)
        .sort((a, b) => b.length - a.length);
    if (taskIds.length === 0) return String(markdown || "");
    const patternSource = String.raw`(^|[^\w\]\)/])#?(${taskIds.map(escapeRegExp).join("|")})(?![\w-])`;
    const pattern = new RegExp(patternSource, "gi");
    return String(markdown || "").replace(pattern, (match, prefix, id) => {
        const task = taskByReference(project, id);
        if (!task) return match;
        return `${prefix || ""}[#${task.id}](sloppy-task:${encodeURIComponent(task.id)})`;
    });
}
