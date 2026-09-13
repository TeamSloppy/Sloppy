// Keep legacy comment classification aligned with TaskComment.effectiveKind.
export function isTechnicalTaskComment(comment) {
  return (comment.kind ?? (comment.authorActorId === "system" ? "technical" : "user_comment")) === "technical";
}
