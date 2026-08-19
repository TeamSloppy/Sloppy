export function imageArtifactFromToolResult(eventItem) {
  const result = eventItem?.type === "tool_result" ? eventItem.toolResult : null;
  if (!result?.ok || String(result.tool || "") !== "images.generate") {
    return null;
  }
  const artifact = result.data?.artifact;
  const id = String(artifact?.id || "").trim();
  if (!id || String(artifact?.kind || "") !== "image") {
    return null;
  }
  return {
    id,
    mediaType: String(artifact.mediaType || "image/png"),
    width: Number.isFinite(Number(artifact.width)) ? Number(artifact.width) : null,
    height: Number.isFinite(Number(artifact.height)) ? Number(artifact.height) : null,
    model: String(result.data?.model || ""),
    modality: String(result.data?.modality || "text_to_image")
  };
}
