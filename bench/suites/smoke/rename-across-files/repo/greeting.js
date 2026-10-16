const { fetchUser } = require("./users");
function greet(id) {
  return `Hello, ${fetchUser(id).name}!`;
}
module.exports = { greet };
