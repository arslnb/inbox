#!/bin/bash
# Builds the app for the App Store and sends it to TestFlight: ios/testflight.sh
#
#   TEAM=<team id>                 your Apple Developer team (developer.apple.com → Membership details)
#   ASC_KEY_ID, ASC_ISSUER_ID,     an App Store Connect API key (Users and Access → Integrations), its .p8 at ASC_KEY_PATH;
#   ASC_KEY_PATH                   without them, the Apple ID signed in to Xcode (Settings → Accounts) signs and uploads
#   ONLY_ARCHIVE=1                 build and sign the archive, send nothing
#
# It records test mode afresh from the mock desk first (npm run ios:demo), so nothing needs recording by hand.
# The build number is the commit count, so each upload from a newer main is newer. MARKETING_VERSION in project.yml is
# the version testers see. Signing is automatic: Xcode makes the distribution certificate and profile the first time.
set -euo pipefail
cd "$(dirname "$0")"

: "${TEAM:?Set TEAM to your Apple Developer team id}"
BUILD=$(git rev-list --count HEAD)
OUT=.build/testflight
rm -rf "$OUT"
mkdir -p "$OUT"

auth=()
if [[ -n "${ASC_KEY_ID:-}" ]]; then
  auth=(-authenticationKeyPath "${ASC_KEY_PATH:?Set ASC_KEY_PATH to the .p8}" -authenticationKeyID "$ASC_KEY_ID"
    -authenticationKeyIssuerID "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID}")
fi

command -v xcodegen >/dev/null && xcodegen generate --quiet

# Test mode from today's mock desk; the committed recording goes back afterwards, so the tree stays as it was.
if git diff --quiet -- Inbox/Demo.json; then trap 'git checkout -- Inbox/Demo.json' EXIT; fi
(cd .. && npm run --silent ios:demo)

echo "Archiving build $BUILD for team $TEAM…"
xcodebuild archive -project Inbox.xcodeproj -scheme Inbox -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$OUT/Inbox.xcarchive" \
  -allowProvisioningUpdates ${auth[@]+"${auth[@]}"} \
  DEVELOPMENT_TEAM="$TEAM" CURRENT_PROJECT_VERSION="$BUILD" -quiet

destination=upload
[[ -n "${ONLY_ARCHIVE:-}" ]] && destination=export
cat >"$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$destination</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

echo "$([[ $destination == upload ]] && echo "Uploading to App Store Connect…" || echo "Exporting the signed .ipa…")"
xcodebuild -exportArchive -archivePath "$OUT/Inbox.xcarchive" -exportPath "$OUT" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates ${auth[@]+"${auth[@]}"}

if [[ $destination == upload ]]; then
  echo "Sent build $BUILD. It shows in App Store Connect → TestFlight once Apple has processed it (a few minutes)."
else
  echo "Signed: $OUT/Inbox.ipa (nothing sent)."
fi
