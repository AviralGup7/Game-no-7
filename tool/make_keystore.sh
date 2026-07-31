#!/usr/bin/env bash
# Generate the Play upload keystore. Run ONCE, then back up the .jks and the
# passwords: losing them means you can never update the app under the same
# Play listing without a key-reset request.
set -euo pipefail
cd "$(dirname "$0")/.."
KS="android/app/upload-keystore.jks"
[ -f "$KS" ] && { echo "$KS exists - refusing to overwrite."; exit 1; }
read -rp  "Key alias [upload]: " ALIAS; ALIAS=${ALIAS:-upload}
read -rsp "Keystore password: " SPW; echo
read -rsp "Confirm password:  " SPW2; echo
[ "$SPW" = "$SPW2" ] || { echo "Passwords do not match."; exit 1; }
[ ${#SPW} -ge 6 ]    || { echo "Password must be 6+ characters."; exit 1; }
keytool -genkey -v -keystore "$KS" -keyalg RSA -keysize 2048 -validity 10000 \
  -alias "$ALIAS" -storepass "$SPW" -keypass "$SPW"
cat > android/key.properties <<EOF
storePassword=$SPW
keyPassword=$SPW
keyAlias=$ALIAS
storeFile=upload-keystore.jks
EOF
chmod 600 android/key.properties "$KS"
echo "Created $KS and android/key.properties (both gitignored). BACK THEM UP."
