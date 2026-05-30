import assert from "node:assert/strict";
import { buildOAuthRedirectURI } from "../src/features/config/oauthRedirect.js";

assert.equal(
  buildOAuthRedirectURI("http://localhost:25102/config"),
  "http://localhost:25102/oauth2callback"
);

assert.equal(
  buildOAuthRedirectURI("http://localhost:25102/config?section=providers"),
  "http://localhost:25102/oauth2callback"
);

assert.equal(
  buildOAuthRedirectURI("http://localhost:25102/nested/path"),
  "http://localhost:25102/oauth2callback"
);
