/** Pure text helpers for speaking assistant replies. No browser or React dependencies. */

const MAX_CHUNK_CHARS = 3000;

/** Removes Markdown markup so it is not read aloud. Pure formatting, no intent detection. */
export function markdownToSpeechText(markdown: string): string {
  return String(markdown || "")
    .replace(/```[\s\S]*?```/g, " ")
    .replace(/!\[[^\]]*\]\([^)]*\)/g, " ")
    .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")
    .replace(/`([^`]*)`/g, "$1")
    .replace(/^\s{0,3}#{1,6}\s+/gm, "")
    .replace(/^\s*[-*+]\s+/gm, "")
    .replace(/(\*\*|__|\*|_|~~)/g, "")
    .replace(/^\s*\|?[-:| ]+\|?\s*$/gm, " ")
    .replace(/\s*\n\s*\n\s*/g, "\n\n")
    .trim();
}

/** Splits text on paragraph, then sentence, boundaries so each chunk fits a TTS request. */
export function splitSpeechChunks(text: string, limit = MAX_CHUNK_CHARS): string[] {
  const chunks: string[] = [];
  let current = "";
  const push = () => {
    if (current.trim()) {
      chunks.push(current.trim());
    }
    current = "";
  };
  const pieces = String(text || "")
    .split(/\n{2,}/)
    .flatMap((paragraph) => (paragraph.length <= limit ? [paragraph] : paragraph.match(/[^.!?。]+[.!?。]*\s*/g) || [paragraph]));
  for (const piece of pieces) {
    const parts = piece.length > limit ? (piece.match(new RegExp(`.{1,${limit}}`, "gs")) || []) : [piece];
    for (const part of parts) {
      if (current.length + part.length + 2 > limit) {
        push();
      }
      current += (current ? "\n\n" : "") + part;
    }
  }
  push();
  return chunks;
}

/**
 * Extracts complete, speakable sentences from a growing text starting at `from`.
 * Text inside an unterminated fenced code block is held back. With `final`, the remainder is flushed.
 * Short fragments are merged so playback is not choppy and requests stay few.
 */
export function extractSpeakableSentences(
  text: string,
  from: number,
  final = false,
  minChars = 40
): { sentences: string[]; nextIndex: number } {
  const fenceCount = (text.match(/```/g) || []).length;
  const limit = fenceCount % 2 === 1 && !final ? text.lastIndexOf("```") : text.length;
  const sentences: string[] = [];
  const boundary = /(?:[.!?…。]+["'»)\]]*(?=\s)|\n{2,})/g;
  let start = Math.min(from, limit);
  let consumed = start;
  boundary.lastIndex = start;
  let match: RegExpExecArray | null;
  while ((match = boundary.exec(text)) !== null && match.index + match[0].length <= limit) {
    const end = match.index + match[0].length;
    const candidate = text.slice(start, end);
    if (candidate.trim().length >= minChars) {
      sentences.push(candidate);
      start = end;
    }
    consumed = start;
  }
  if (final && limit > start) {
    const rest = text.slice(start, limit);
    if (rest.trim()) {
      sentences.push(rest);
    }
    consumed = limit;
  }
  return { sentences, nextIndex: consumed };
}
