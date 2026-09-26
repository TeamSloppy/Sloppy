export function webArtifactFromToolResult(eventItem) {
  const result = eventItem?.type === "tool_result" ? eventItem.toolResult : null;
  if (!result?.ok || result.tool !== "artifacts.web.create") {
    return null;
  }
  const artifact = result.data?.artifact;
  const id = String(artifact?.id || "").trim();
  if (!id || artifact?.kind !== "widget" || artifact?.mediaType !== "text/html") {
    return null;
  }
  return {
    id,
    title: String(artifact.title || "Web visual"),
    summary: String(artifact.previewText || "")
  };
}
