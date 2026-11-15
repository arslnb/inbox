#!/usr/bin/env bash
# npm run release:publish v0.2.4: pushes main and the tag, builds them for macOS, Windows and Linux on this Mac, and
# publishes the GitHub Release. --build-only builds and stops; --upload-only publishes what's in release/ (a failed
# upload's retry, with no rebuild).
set -euo pipefail

tag=${1:?usage: npm run release:publish vX.Y.Z [-- --build-only | --upload-only]}
only=${2:-}
repo=gricha/inbox
root=$(git rev-parse --show-toplevel)
cd "$root"

[ "$(uname)" = Darwin ] || { echo "release:publish builds the Mac app: run it on macOS" >&2; exit 1; }
git rev-parse -q --verify "refs/tags/$tag" >/dev/null || { echo "$tag isn't a tag: npm run release ${tag#v} first" >&2; exit 1; }
version=$(git show "$tag:package.json" | node -p 'JSON.parse(require("fs").readFileSync(0, "utf8")).version')
[ "v$version" = "$tag" ] || { echo "$tag, but its package.json says $version" >&2; exit 1; }
released=$(gh release view "$tag" -R "$repo" --json assets --jq '.assets | length' 2>/dev/null || echo none)
if [ -z "$only" ] && [ "$released" != none ]; then
  echo "$tag is already released" >&2
  exit 1
fi

# Every build, and the files the updater reads; the Linux tar.gz is named like the rest (package.json's linux.artifactName).
assets() {
  shopt -s nullglob
  local dir=$1 f builds=("$1"/*"-$version"*)
  [ "${#builds[@]}" -gt 0 ] || return 0
  printf '%s\n' "${builds[@]}"
  # The updater's files only when they're this version's: a stale one would point every app at an older build.
  for f in "$dir"/latest*.yml; do grep -qx "version: $version" "$f" && echo "$f"; done
  return 0
}

# The Release, from what's in a folder: a new one, or the files a failed upload left out of one that exists.
publish() {
  local dir=$1 files=() f
  while IFS= read -r f; do files+=("$f"); done < <(assets "$dir")
  [ "${#files[@]}" -gt 0 ] || { echo "no $tag builds in $dir: build them first" >&2; exit 1; }
  if [ "$released" = none ]; then
    gh release create "$tag" "${files[@]}" -R "$repo" --verify-tag --title "Inbox $version" --generate-notes
  else
    gh release upload "$tag" "${files[@]}" -R "$repo" --clobber
  fi
  echo "Published https://github.com/$repo/releases/tag/$tag"
}

if [ "$only" = --upload-only ]; then
  publish "$root/release"
  exit 0
fi

wt=$root/.claude/worktrees/release-$tag
rm -rf "$wt"
git worktree add --quiet --detach "$wt" "$tag"
trap 'git -C "$root" worktree remove --force "$wt"' EXIT
cp -cR node_modules "$wt/node_modules"
cd "$wt"

npm run -s check
# Then main and the tag, together, before minutes of building: a main that moved on GitHub since the tag refuses here.
if [ "$only" != --build-only ]; then
  git -C "$root" push --atomic origin "$tag^{commit}:refs/heads/main" "refs/tags/$tag" || {
    echo "main moved on GitHub since $tag: git fetch, git tag -d $tag, git reset --hard origin/main, then npm run release again" >&2
    exit 1
  }
fi
npm run -s build
# Each platform at once: compressing the installers is most of the time, and they don't share files. Apart, too, because
# arch flags apply to every platform named, and Windows and Linux are x64 only (package.json's build).
npx electron-builder --mac --arm64 --x64 --publish never > release-mac.log 2>&1 &
mac=$!
npx electron-builder --win --publish never > release-win.log 2>&1 &
win=$!
npx electron-builder --linux --publish never > release-linux.log 2>&1 &
linux=$!
for p in "mac $mac" "win $win" "linux $linux"; do
  set -- $p
  wait "$2" || { echo "the $1 build failed:" >&2; tail -30 "release-$1.log" >&2; exit 1; }
done

# Kept beside the checkout whatever happens next, so a failed upload is retried with --upload-only, not a rebuild.
rm -rf "$root/release" && cp -R release "$root/release"
assets "$root/release"
if [ "$only" = --build-only ]; then
  echo "Built $tag into release/; nothing pushed or published"
  exit 0
fi
publish "$root/release" || {
  echo "the upload failed; the builds are in release/: npm run release:publish $tag -- --upload-only" >&2
  exit 1
}
