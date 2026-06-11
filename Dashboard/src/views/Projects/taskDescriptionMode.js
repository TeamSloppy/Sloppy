export function taskDescriptionMode(description, isEditing) {
    const hasDescription = String(description || "").trim().length > 0;
    if (isEditing || !hasDescription) {
        return "editor";
    }
    return "preview";
}
