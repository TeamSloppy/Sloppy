function fetchUser(id) {
  return { id, name: `user-${id}` };
}
module.exports = { fetchUser };
