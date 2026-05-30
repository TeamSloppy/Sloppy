export function buildOAuthRedirectURI(currentURL) {
  const url = new URL(currentURL);
  url.pathname = "/oauth2callback";
  url.search = "";
  url.hash = "";
  return url.toString();
}
