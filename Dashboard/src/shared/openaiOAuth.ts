export const OPENAI_OAUTH_MESSAGE_TYPE = "sloppy:openai-oauth";

export interface OpenAIOAuthWindowMessage {
  type: string;
  ok: boolean;
  message: string;
  accountId?: string | null;
  planType?: string | null;
}

const OPENAI_OAUTH_CALLBACK_PARAMS = ["code", "state", "error", "error_description"];

export function buildOpenAIOAuthRedirectURI() {
  return `${window.location.origin}${window.location.pathname}`;
}

export function readOpenAIOAuthCallbackURL() {
  const url = new URL(window.location.href);
  const hasCallbackParams = OPENAI_OAUTH_CALLBACK_PARAMS.some((key) => url.searchParams.has(key));
  return hasCallbackParams ? url.toString() : null;
}

export function readOpenAIOAuthCallbackError() {
  const url = new URL(window.location.href);
  const error = url.searchParams.get("error");
  if (!error) {
    return "";
  }

  const description = url.searchParams.get("error_description");
  return description ? `${error}: ${description}` : error;
}

export function clearOpenAIOAuthCallbackParams() {
  const url = new URL(window.location.href);
  OPENAI_OAUTH_CALLBACK_PARAMS.forEach((key) => url.searchParams.delete(key));
  const search = url.searchParams.toString();
  window.history.replaceState({}, "", `${url.pathname}${search ? `?${search}` : ""}${url.hash}`);
}

export function openOpenAIOAuthPopup(authorizationURL: string) {
  const width = 640;
  const height = 860;
  const left = Math.max(0, Math.round(window.screenX + (window.outerWidth - width) / 2));
  const top = Math.max(0, Math.round(window.screenY + (window.outerHeight - height) / 2));
  return window.open(
    authorizationURL,
    "sloppy-openai-oauth",
    `popup=yes,width=${width},height=${height},left=${left},top=${top},noopener=no,noreferrer=no`
  );
}

export function postOpenAIOAuthMessage(message: Omit<OpenAIOAuthWindowMessage, "type">) {
  if (!window.opener || window.opener === window) {
    return;
  }

  window.opener.postMessage(
    {
      type: OPENAI_OAUTH_MESSAGE_TYPE,
      ...message
    },
    window.location.origin
  );
}
