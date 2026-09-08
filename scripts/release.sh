#!/usr/bin/env bash
# Publish a new release in one command.
#
#   bash scripts/release.sh v0.4.1
#
# Guardrails:
#   - refuses a dirty working tree
#   - refuses an already-existing tag
#   - checks the tag version matches export_presets.cfg `version/name`
#   - pushes an annotated tag; CI (tag push or `release: published`) then
#     builds, tests, exports the APK and publishes the GitHub Release.
#
# Note: if the CI "Publish release" step fails on workflow_dispatch from the
# UI, the tag-push path always works — it needs no extra permissions.
set -euo pipefail

TAG="${1:-}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

usage() {
  echo "usage: bash scripts/release.sh vX.Y.Z   (e.g. v0.4.1)" >&2
  exit 2
}

[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || usage

# --- guardrail: clean tree -------------------------------------------------
if [[ -n "$(git status --porcelain)" ]]; then
  echo "ERROR: working tree is dirty — commit or stash first:" >&2
  git status --short >&2
  exit 1
fi

# --- guardrail: tag must not exist (locally or on origin) -------------------
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "ERROR: tag $TAG already exists locally." >&2
  exit 1
fi
if git ls-remote --tags origin "refs/tags/$TAG" | grep -q .; then
  echo "ERROR: tag $TAG already exists on origin." >&2
  exit 1
fi

# --- guardrail: version/name matches export_presets.cfg ---------------------
VERSION="${TAG#v}"
PRESET_VERSION="$(sed -n 's/^version\/name="\([^"]*\)"/\1/p' export_presets.cfg | head -1)"
if [[ "$PRESET_VERSION" != "$VERSION" ]]; then
  echo "ERROR: export_presets.cfg version/name is '$PRESET_VERSION' but tag is '$TAG'." >&2
  echo "Bump version/name in export_presets.cfg first, commit, then re-run." >&2
  exit 1
fi

# --- guardrail: CHANGELOG mentions the version ------------------------------
if ! grep -q "$TAG" CHANGELOG.md; then
  echo "ERROR: CHANGELOG.md does not mention $TAG — add a release entry first." >&2
  exit 1
fi

# --- ship it ----------------------------------------------------------------
git tag -a "$TAG" -m "Release $TAG (APK published by CI)"
git push origin "refs/tags/$TAG"

echo ""
echo "Tag $TAG pushed. CI is now building + publishing:"
echo "  https://github.com/$(git remote get-url origin | sed -E 's#.*github.com[:/]##; s#\.git$##')/actions"
echo "The Release will appear at: .../releases/tag/$TAG"
