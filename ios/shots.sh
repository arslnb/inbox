#!/bin/sh
# Builds the app, runs it in the booted Simulator against the mock desk, and writes a PNG of each state into ios/.shots/,
# in light and dark. Look at them after any change to the app: ios/README.md says what to look for.
#
#   ios/shots.sh                  every state
#   ios/shots.sh inbox item-pr    only these
#
# SHOTS_UDID picks a simulator (default: the booted one); SHOTS_PORT the mock's port (default 47841).
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$HERE")
PORT=${SHOTS_PORT:-47841}
DESK="http://localhost:$PORT"
OUT="$HERE/.shots"
BUNDLE=dev.inbox.ios
PATH="/opt/homebrew/bin:$PATH"

UDID=${SHOTS_UDID:-$(xcrun simctl list devices booted | sed -n 's/.*(\([0-9A-F-]\{36\}\)) (Booted).*/\1/p' | head -1)}
[ -n "$UDID" ] || { echo "No booted simulator: open Simulator (or xcrun simctl boot \"iPhone 17 Pro\") first." >&2; exit 1; }

# A desk already on the port (a mock started by hand, with whatever was done to it since) would be shot in the mock's place.
if curl -fs "$DESK/health" >/dev/null 2>&1; then
  echo "Something already answers on port $PORT: stop it first (or set SHOTS_PORT), so the shots are of a fresh mock." >&2
  exit 1
fi

echo "Building…"
mkdir -p "$HERE/.build"
xcodebuild -project "$HERE/Inbox.xcodeproj" -scheme Inbox -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$HERE/.build" build >"$HERE/.build/shots-build.log" 2>&1 ||
  { tail -30 "$HERE/.build/shots-build.log" >&2; exit 1; }
xcrun simctl install "$UDID" "$HERE/.build/Build/Products/Debug-iphonesimulator/Inbox.app"

# The mock desk, for as long as this script runs. Its dates are relative to its start, so ages read the same every run.
(cd "$ROOT" && MOCK_PORT=$PORT MOCK_NO_POLL=1 exec node --disable-warning=ExperimentalWarning web/mock/server.ts) >/dev/null 2>&1 &
MOCK=$!
cleanup() {
  kill "$MOCK" 2>/dev/null || true
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl status_bar "$UDID" clear >/dev/null 2>&1 || true
  xcrun simctl ui "$UDID" appearance light >/dev/null 2>&1 || true
  xcrun simctl ui "$UDID" content_size large >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM
i=0
until curl -fs "$DESK/health" >/dev/null 2>&1; do
  i=$((i + 1))
  [ "$i" -lt 50 ] || { echo "The mock desk didn't start on port $PORT (is it taken, or is npm install needed?)." >&2; exit 1; }
  sleep 0.2
done

mkdir -p "$OUT"
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 >/dev/null 2>&1 || true

# name, then the launch arguments that reach it (Store.applyLaunchArguments, DEBUG builds only).
shot() {
  name=$1
  shift
  # Where a review has steps the diff opens Guided, whatever was last chosen on this simulator.
  case "$*" in *review.view*) ;; *) set -- "$@" -review.view guided ;; esac
  for look in light dark; do
    xcrun simctl ui "$UDID" appearance "$look"
    xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
    xcrun simctl launch "$UDID" "$BUNDLE" "$@" >/dev/null
    sleep "${SHOTS_WAIT:-3}"
    xcrun simctl io "$UDID" screenshot "$OUT/$name-$look.png" >/dev/null 2>&1
    echo "  $name-$look.png"
  done
}

wanted() {
  [ -z "$ONLY" ] && return 0
  for w in $ONLY; do [ "$w" = "$1" ] && return 0; done
  return 1
}
ONLY="$*"

wanted connect && shot connect -connect
wanted connect-error && shot connect-error -connect -connectAddress "https://desk.tail1234.ts.net" \
  -connectError "That pairing code isn't valid: run desk pair again for a new one."
# What the camera would have read (the Simulator has none): a QR that isn't a desk's never leaves the connect screen.
wanted connect-scan-wrong && shot connect-scan-wrong -connect -scan "https://example.com"
wanted inbox && shot inbox -deskURL "$DESK"
wanted inbox-scrolled && shot inbox-scrolled -deskURL "$DESK" -scrollTo standard
wanted inbox-empty && shot inbox-empty -deskURL "$DESK" -empty
# The filter: its suggestions with the cursor in the box, a person as a pill with what matches, and the other two pages
# it's on (Blocked lies flat and counts "n of m"; the Archive opens the groups with a match).
wanted inbox-filter && shot inbox-filter -deskURL "$DESK" -filterFocus
wanted inbox-filter-author && shot inbox-filter-author -deskURL "$DESK" -filter "author:dana "
wanted inbox-filter-large && shot inbox-filter-large -deskURL "$DESK" -filter "involves:priya " -filterFocus \
  -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL
wanted blocked-filter && shot blocked-filter -deskURL "$DESK" -page blocked -filter "web"
wanted archive-filter && shot archive-filter -deskURL "$DESK" -page archive -filter "involves:marco "
# FYI's first five and Show 3 more: the mock's FYI has six, which all show, so two of Standard's are moved there and back.
if wanted inbox-fyi; then
  for id in "acme/api#3052" "acme/api#3053"; do
    curl -fs -X POST -H "Content-Type: application/json" -d "{\"id\":\"$id\",\"action\":\"fyi\"}" "$DESK/api/act" >/dev/null
  done
  shot inbox-fyi -deskURL "$DESK" -scrollTo fyi
  for id in "acme/api#3052" "acme/api#3053"; do
    curl -fs -X POST -H "Content-Type: application/json" -d "{\"id\":\"$id\",\"action\":\"standard\"}" "$DESK/api/act" >/dev/null
  done
fi
# The note box: a new note, and one opened with its reminder.
wanted note-new && shot note-new -deskURL "$DESK" -note new
wanted note-edit && shot note-edit -deskURL "$DESK" -note n3
wanted blocked && shot blocked -deskURL "$DESK" -page blocked
wanted merging && shot merging -deskURL "$DESK" -page merging
wanted archive && shot archive -deskURL "$DESK" -page archive
wanted item-pr && shot item-pr -deskURL "$DESK" -open "acme/api#4127"
# A PR's State: its checks opened to each by name (a failing run), and your own PR's reviewers with + Add reviewers.
wanted item-pr-checks && shot item-pr-checks -deskURL "$DESK" -open "oss/tinyhttp#205" -part checks
wanted item-pr-own && shot item-pr-own -deskURL "$DESK" -open "acme/worker#875" -part reviewers
# A PR's diff: scrolled to its first file, a thread under its line, and the box for a comment on a line.
wanted item-pr-diff && shot item-pr-diff -deskURL "$DESK" -open "acme/api#4127" -scroll diff -review.view traditional
wanted item-pr-diff-thread && shot item-pr-diff-thread -deskURL "$DESK" -open "acme/api#4127" -scroll thread -review.view traditional
wanted item-pr-line-comment && shot item-pr-line-comment -deskURL "$DESK" -open "acme/api#4127" -scroll diff -comment "src/planner/stream.ts:12" -review.view traditional
# The AI review: its fold opened (a goal, interfaces, could be better), a step of the guide with its diagram as text,
# its notes on a line, and where a review stands: on an earlier commit, failed, being written, none.
wanted item-pr-ai-open && shot item-pr-ai-open -deskURL "$DESK" -open "acme/worker#879" -ai open
wanted item-pr-guided && shot item-pr-guided -deskURL "$DESK" -open "acme/worker#879" -scroll guide
wanted item-pr-guided-note && shot item-pr-guided-note -deskURL "$DESK" -open "acme/worker#879" -scroll note
wanted item-pr-guided-end && shot item-pr-guided-end -deskURL "$DESK" -open "acme/api#4127" -scroll step-3
wanted item-pr-ai-stale && shot item-pr-ai-stale -deskURL "$DESK" -open "acme/api#4099"
wanted item-pr-ai-failed && shot item-pr-ai-failed -deskURL "$DESK" -open "acme/worker#890"
wanted item-pr-ai-running && shot item-pr-ai-running -deskURL "$DESK" -open "acme/web#2301"
# None: with the desk's own reviews off, so opening it starts none (the mock's setting, put back after).
if wanted item-pr-ai-none; then
  curl -fs -X PUT -H "Content-Type: application/json" -d '{"set":{"review.auto_ai":false}}' "$DESK/api/settings" >/dev/null
  shot item-pr-ai-none -deskURL "$DESK" -open "acme/ml-pipeline#307"
  curl -fs -X PUT -H "Content-Type: application/json" -d '{"set":{"review.auto_ai":true}}' "$DESK/api/settings" >/dev/null
fi
# An issue: its pre-review with Make PR with fix, a walk at its second step, and what the mock never sends (-issue cuts
# it from what it does): a flagged one with Block, none yet with Analyze it, a blocked author with Unblock.
wanted item-issue && shot item-issue -deskURL "$DESK" -open "acme/worker#860"
wanted item-issue-step && shot item-issue-step -deskURL "$DESK" -open "acme/api#4071" -step 2
wanted item-issue-injection && shot item-issue-injection -deskURL "$DESK" -open "acme/worker#860" -issue injection
wanted item-issue-none && shot item-issue-none -deskURL "$DESK" -open "acme/worker#860" -issue none
wanted item-issue-blocked && shot item-issue-blocked -deskURL "$DESK" -open "acme/worker#860" -issue blocked
# Yours: one that owes a reply (what was said, and Reply), a draft, one through review, one in Merging.
wanted item-reply && shot item-reply -deskURL "$DESK" -open "me/notes-app#12"
# What reviewers said: the first waiting one's own words unfolded, and the ones not waiting on you opened in place.
wanted item-pr-said && shot item-pr-said -deskURL "$DESK" -open "me/notes-app#12" -said waiting
wanted item-pr-more-conversations && shot item-pr-more-conversations -deskURL "$DESK" -open "me/notes-app#12" -said more -scroll said
wanted item-draft && shot item-draft -deskURL "$DESK" -open "acme/web#2303"
wanted item-mine && shot item-mine -deskURL "$DESK" -open "acme/worker#875"
wanted item-merging && shot item-merging -deskURL "$DESK" -page merging -open "acme/api#4122"
# The boxes that write (-box opens one once its page has loaded).
wanted approve && shot approve -deskURL "$DESK" -open "acme/api#4127" -box approve
wanted reply && shot reply -deskURL "$DESK" -open "me/notes-app#12" -box reply
wanted reviewers && shot reviewers -deskURL "$DESK" -open "acme/worker#875" -box reviewers
wanted question && shot question -deskURL "$DESK" -open "inquiry:q1c0ffee"
wanted answer && shot answer -deskURL "$DESK" -open "inquiry:q1c0ffee" -box answer
wanted session && shot session -deskURL "$DESK" -open "session:5f1c2a90-7d3e-4b8a-9c11-2e6f0a4b7d21"
wanted session-kick && shot session-kick -deskURL "$DESK" -open "session:a83e61d4-0b52-4f7c-8e3a-91c4d6b2f058"
# Accessibility text sizes: the bar's quiet buttons fold into More rather than clip; at the largest, with the longest
# call to action, More is its dots, the button keeps its words and the lines changed go under the ref.
if wanted item-large; then
  xcrun simctl ui "$UDID" content_size accessibility-large
  shot item-large -deskURL "$DESK" -open "acme/api#4127"
  xcrun simctl ui "$UDID" content_size large
fi
if wanted item-pr-guided-large; then
  xcrun simctl ui "$UDID" content_size accessibility-large
  shot item-pr-guided-large -deskURL "$DESK" -open "acme/worker#879" -scroll guide
  xcrun simctl ui "$UDID" content_size large
fi
# The size as a launch argument: it holds on a simulator that doesn't take `simctl ui content_size`.
wanted item-issue-large && shot item-issue-large -deskURL "$DESK" -open "acme/api#4071" -step 2 \
  -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL
if wanted item-largest; then
  xcrun simctl ui "$UDID" content_size accessibility-extra-extra-extra-large
  shot item-largest -deskURL "$DESK" -open "acme/worker#875"
  xcrun simctl ui "$UDID" content_size large
fi
wanted settings && shot settings -deskURL "$DESK" -settings
# A desk that isn't there: nothing listens on port 9.
wanted offline && shot offline -deskURL "http://localhost:9"

echo "Wrote $OUT"
