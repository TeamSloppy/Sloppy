function readPort(env) {
  const raw = env.PORT;
  return raw === undefined ? undefined : Number(raw);
}
module.exports = { readPort };
