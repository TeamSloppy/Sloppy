const defaults = require("./defaults");
const { readPort } = require("./env");
function loadConfig(env) {
  return { ...defaults, port: readPort(env), host: env.HOST || defaults.host };
}
module.exports = { loadConfig };
