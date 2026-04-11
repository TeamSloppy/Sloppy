/**
 * Mirrors Sources/PluginSDK/ChannelGatewayScope.swift — Telegram topic-scoped channel ids.
 */

const UNIT_SEP = "\u001E";
const TOPIC_MARKER = "tgthread:";

const NEEDLE = `${UNIT_SEP}${TOPIC_MARKER}`;

/** Base gateway binding id (strip `\u001Etgthread:…` suffix when present). */
export function gatewayBindingChannelId(channelId) {
  const raw = String(channelId || "").trim();
  const idx = raw.indexOf(NEEDLE);
  if (idx === -1) {
    return raw;
  }
  const base = raw.slice(0, idx).trim();
  return base || raw;
}

/**
 * Whether an open session belongs to this project/binding channel (exact base or topic under that base).
 */
export function sessionChannelMatchesBinding(sessionChannelId, bindingChannelId) {
  const binding = String(bindingChannelId || "").trim();
  const session = String(sessionChannelId || "").trim();
  if (!binding) {
    return false;
  }
  if (session === binding) {
    return true;
  }
  return session.startsWith(`${binding}${NEEDLE}`);
}
