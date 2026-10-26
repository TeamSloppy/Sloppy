export type TextSearchMode = "text" | "words";
export interface TextSearchHit {
  id: string;
  source: "agent" | "channel";
  agentId?: string;
  sessionId: string;
  projectId?: string;
  title: string;
  eventId: string;
  messageId?: string;
  before: string;
  kind: string;
  role?: string;
  createdAt: string;
  snippet: string;
}
export interface TextSearchResponse {
  items: TextSearchHit[];
  hasMore: boolean;
  indexing: boolean;
  indexedSources: number;
  failedSources: number;
  durationMs: number;
}
export interface TextSearchDocument { hit: TextSearchHit; text: string; }
