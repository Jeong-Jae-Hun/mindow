#!/usr/bin/env bash
# Builds, signs, notarizes and publishes a Mindow release in two phases, because
# notarization is asynchronous and can take from minutes to hours.
#
#   ./scripts/release.sh                 # archive, sign, zip, submit for notarization
#   PHASE=publish ./scripts/release.sh   # if accepted: staple, zip, GitHub Release
#   DRY_RUN=1 ./scripts/release.sh       # ad-hoc signed build only, no Apple account
#
# Needs an unlocked login keychain: run it from a local Terminal, or unlock first
# over SSH (`security unlock-keychain`), otherwise codesign fails with
# errSecInternalComponent.
#
# Env for a real release (keep these out of the repo and CI):
#   APPLE_SIGNING_IDENTITY  "Developer ID Application: Name (TEAMID)"
#   APPLE_ASC_KEY_ID, APPLE_ASC_ISSUER_ID, APPLE_ASC_KEY_P8 (the .p8 contents)
set -euo pipefail
# Keep the key out of every child process, including dry runs; only this shell reads it.
export -n APPLE_ASC_KEY_P8 2>/dev/null || true
cd "$(dirname "$0")/.."

PHASE=${PHASE:-submit}
DRY_RUN=${DRY_RUN:-0}
VERSION=$(sed -n "s/^ *MARKETING_VERSION: *//p" project.yml)
OUT="build/release/$VERSION"
APP="$OUT/Mindow.app"
ZIP="$OUT/Mindow-$VERSION.zip"
ID_FILE="$OUT/notary-id"
COMMIT_FILE="$OUT/commit"
SHA_FILE="$ZIP.sha256"

die() { echo "error: $*" >&2; exit 1; }

CLEANUP=()
# The +-expansion keeps an empty array safe under `set -u` in macOS's bash 3.2.
trap 'rm -rf ${CLEANUP[@]+"${CLEANUP[@]}"}' EXIT

# One run per version at a time, so the zip cannot change between hashing and upload.
mkdir -p "build/release"
LOCK="build/release/.lock-$VERSION"
mkdir "$LOCK" 2>/dev/null || die "another release run for $VERSION holds $LOCK"
CLEANUP+=("$LOCK")

NOTARY=()
if [ "$DRY_RUN" = 0 ]; then
  : "${APPLE_SIGNING_IDENTITY:?}" "${APPLE_ASC_KEY_ID:?}" "${APPLE_ASC_ISSUER_ID:?}" "${APPLE_ASC_KEY_P8:?}"
  # notarytool only takes the key as a file path. Keep it private, remove it on
  # exit, and drop the variable so xcodebuild, git and gh do not inherit it.
  KEYDIR=$(mktemp -d)
  CLEANUP+=("$KEYDIR")
  (umask 077 && printf "%s" "$APPLE_ASC_KEY_P8" > "$KEYDIR/AuthKey.p8")
  unset APPLE_ASC_KEY_P8
  NOTARY=(--key "$KEYDIR/AuthKey.p8" --key-id "$APPLE_ASC_KEY_ID" --issuer "$APPLE_ASC_ISSUER_ID")
fi

if [ "$PHASE" = submit ]; then
  [ -z "$(git status --porcelain)" ] || die "working tree is dirty; commit first"
  ! git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null || die "v$VERSION exists; bump MARKETING_VERSION"

  rm -rf "$OUT" && mkdir -p "$OUT"
  git rev-parse HEAD > "$COMMIT_FILE"
  if [ "$DRY_RUN" = 0 ]; then
    SIGN=(CODE_SIGN_IDENTITY="$APPLE_SIGNING_IDENTITY" CODE_SIGN_STYLE=Manual OTHER_CODE_SIGN_FLAGS=--timestamp)
  else
    SIGN=(CODE_SIGN_IDENTITY=-)
  fi
  xcodebuild -project Mindow.xcodeproj -scheme Mindow -configuration Release \
    -archivePath "$OUT/Mindow.xcarchive" "${SIGN[@]}" archive -quiet
  ditto "$OUT/Mindow.xcarchive/Products/Applications/Mindow.app" "$APP"
  codesign --verify --deep --strict "$APP"

  if [ "$DRY_RUN" = 1 ]; then
    echo "dry run: ad-hoc signed $APP"
    exit 0
  fi
  SIGNATURE=$(codesign -dv "$APP" 2>&1)
  [[ "$SIGNATURE" == *"Authority=Developer ID Application"* ]] \
    || die "$APP is not signed with a Developer ID certificate"

  ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
  xcrun notarytool submit "$OUT/notarize.zip" "${NOTARY[@]}" --no-wait --output-format json \
    | plutil -extract id raw - > "$ID_FILE"
  echo "submitted $(cat "$ID_FILE"). Run PHASE=publish $0 once Apple accepts it."
  exit 0
fi

[ "$PHASE" = publish ] || die "unknown PHASE=$PHASE"
[ "$DRY_RUN" = 0 ] || die "DRY_RUN only applies to the submit phase"
[ -f "$ID_FILE" ] || die "no submission for $VERSION; run the submit phase first"
ID=$(cat "$ID_FILE")
STATUS=$(xcrun notarytool info "$ID" "${NOTARY[@]}" --output-format json | plutil -extract status raw -)
case "$STATUS" in
  Accepted) ;;
  "In Progress") echo "notarization still in progress; run again later"; exit 75 ;;
  *) xcrun notarytool log "$ID" "${NOTARY[@]}" >&2 || true; die "notarization $STATUS" ;;
esac

COMMIT=$(cat "$COMMIT_FILE")

# The zip and its hash are fixed once; reruns after a failed push or upload reuse
# them, so the published SHA-256 always belongs to the uploaded file.
if [ ! -f "$SHA_FILE" ]; then
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl --assess --type execute "$APP"
  ditto -c -k --keepParent "$APP" "$ZIP.partial"
  mv "$ZIP.partial" "$ZIP"
  shasum -a 256 "$ZIP" | cut -d " " -f 1 > "$SHA_FILE.partial"
  mv "$SHA_FILE.partial" "$SHA_FILE"
fi
SHA=$(cat "$SHA_FILE")
[ "$(shasum -a 256 "$ZIP" | cut -d " " -f 1)" = "$SHA" ] || die "$ZIP no longer matches $SHA_FILE"

# Tag the commit that was built and submitted, not whatever HEAD is now.
if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
  [ "$(git rev-parse "v$VERSION^{commit}")" = "$COMMIT" ] || die "tag v$VERSION points elsewhere than $COMMIT"
else
  git tag "v$VERSION" "$COMMIT"
fi
git push origin "refs/tags/v$VERSION"

# An interrupted `gh release create` can leave a draft without the zip. Never
# patch a release in place; stop and let a person decide.
if gh release view "v$VERSION" >/dev/null 2>&1; then
  STATE=$(gh release view "v$VERSION" --json isDraft,assets \
    --jq "[.isDraft, ([.assets[] | select(.name == \"Mindow-$VERSION.zip\") | .digest] | join(\",\"))] | @tsv")
  [ "$STATE" = "$(printf "false\tsha256:%s" "$SHA")" ] \
    || die "release v$VERSION does not hold exactly this zip (draft, missing, or another sha256); inspect it on GitHub"
  echo "release v$VERSION already published; its assets are left untouched"
else
  gh release create "v$VERSION" "$ZIP" --verify-tag --title "Mindow $VERSION" \
    --notes "Signed with Developer ID and notarized by Apple.

SHA-256 of Mindow-$VERSION.zip: \`$SHA\`"
fi
echo "released v$VERSION ($COMMIT), sha256 $SHA. Update the Homebrew cask with this sha256."
