#!/usr/bin/env bash
#
# Build a signed, universal release of Segue and package it for GitHub.
# Releases are built and signed locally; there is no CI.
#
#   scripts/release.sh X.Y.Z [--identity NAME] [--dry-run]
#
#   --identity   code-signing identity (default "Segue Release"; "-" = ad-hoc)
#   --dry-run    don't bump the version, commit or tag; sign ad-hoc; just
#                prove the universal build and zip work
#
# Steps: check the tree is clean → set the version in Version.swift and commit
# → make test → universal bundle signed with the release identity → verify →
# dist/Segue-X.Y.Z.zip + .sha256 → git tag vX.Y.Z. Then, by hand:
#   gh release create vX.Y.Z dist/Segue-X.Y.Z.zip dist/Segue-X.Y.Z.zip.sha256 --title vX.Y.Z --generate-notes
#   scripts/update-tap.sh --tap ~/GitProjects/personal/homebrew-tap --version X.Y.Z --zip dist/Segue-X.Y.Z.zip
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"; shift || true
IDENTITY="Segue Release"
DRY_RUN=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --identity) IDENTITY="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; IDENTITY="-"; shift ;;
        *) echo "error: unknown argument '$1'" >&2; exit 2 ;;
    esac
done
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: scripts/release.sh X.Y.Z [--identity NAME] [--dry-run]" >&2; exit 2; }

step() { printf '\n==> %s\n' "$1"; }

if [[ "$DRY_RUN" == 0 ]]; then
    if [[ -n "$(git status --porcelain)" ]]; then
        echo "error: the working tree is not clean" >&2; exit 1
    fi
    if [[ "$IDENTITY" != "-" ]] && ! security find-identity -v -p codesigning 2>/dev/null | grep -qF "$IDENTITY"; then
        echo "error: no code-signing identity named '$IDENTITY'. Run scripts/create-release-cert.sh (yourself, at the keyboard)." >&2
        exit 1
    fi
    step "Setting version $VERSION"
    sed -i '' -E "s/(static let string = \")[^\"]+(\")/\1$VERSION\2/" Sources/SegueCore/Version.swift
    git add Sources/SegueCore/Version.swift
    git commit -q -m "Release $VERSION" || true
fi

step "Running tests"
swift test 2>&1 | grep -E 'Executed .* tests' | tail -1

step "Building the universal bundle (identity '$IDENTITY')"
BUILD_NUMBER="$(git rev-list --count HEAD)" UNIVERSAL=1 CODESIGN_IDENTITY="$IDENTITY" scripts/bundle.sh

step "Verifying"
lipo -info build/Segue.app/Contents/MacOS/Segue
codesign --verify --strict --verbose=2 build/Segue.app
codesign -d -r- build/Segue.app 2>&1 | grep designated

step "Packaging"
mkdir -p dist
ZIP="dist/Segue-$VERSION.zip"
rm -f "$ZIP" "$ZIP.sha256"
ditto -c -k --keepParent build/Segue.app "$ZIP"
(cd dist && shasum -a 256 "Segue-$VERSION.zip" > "Segue-$VERSION.zip.sha256")
cat "$ZIP.sha256"
du -h "$ZIP" | cut -f1

if [[ "$DRY_RUN" == 0 ]]; then
    step "Tagging v$VERSION"
    git tag -a "v$VERSION" -m "Segue $VERSION"
    echo
    echo "Next:"
    echo "  gh release create v$VERSION $ZIP $ZIP.sha256 --title v$VERSION --generate-notes"
    echo "  scripts/update-tap.sh --tap ~/GitProjects/personal/homebrew-tap --version $VERSION --zip $ZIP"
else
    echo
    echo "Dry run complete (no commit, no tag, ad-hoc signature)."
fi
