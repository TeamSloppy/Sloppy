set -e
node test.js
if grep -rn "fetchUser" --include=*.js . ; then
  echo "fetchUser still referenced"
  exit 1
fi
grep -q "loadUser" users.js greeting.js report.js
