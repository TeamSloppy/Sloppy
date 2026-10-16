const { fetchUser } = require("./users");
function report(ids) {
  return ids.map((id) => fetchUser(id).name).join(", ");
}
module.exports = { report };
