#!/usr/bin/env bash
# Consumer git hooks: refuse main/master commits and pushes, refuse non-ff pushes,
# and chain an existing hooksPath instead of replacing it.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
INSTALL="$ROOT/core/scripts/install-githooks.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

git init -q --bare -b main "$TMP/bare"
git init -q -b main "$TMP/repo"
git -C "$TMP/repo" commit -q --allow-empty -m init
git -C "$TMP/repo" remote add origin "$TMP/bare"
git -C "$TMP/repo" push -q -u origin main

# Legacy default hook must still run after we set core.hooksPath.
mkdir -p "$TMP/repo/.git/hooks"
cat >"$TMP/repo/.git/hooks/pre-commit" <<'EOF'
#!/bin/sh
echo legacy >> "$(git rev-parse --git-dir)/legacy-ran"
EOF
chmod +x "$TMP/repo/.git/hooks/pre-commit"

"$INSTALL" --workdir "$TMP/repo" >/dev/null
hooks_path="$(git -C "$TMP/repo" config --get core.hooksPath || true)"
if [[ "$hooks_path" == ".relentless/githooks" ]]; then ok; else bad "hooksPath=$hooks_path"; fi
if [[ -x "$TMP/repo/.relentless/githooks/pre-commit" && -x "$TMP/repo/.relentless/githooks/pre-push" ]]; then
  ok
else
  bad "hook scripts missing"
fi

git -C "$TMP/repo" checkout -q -b feat/1-x
git -C "$TMP/repo" commit -q --allow-empty -m feat
if [[ -f "$TMP/repo/.git/legacy-ran" ]]; then ok; else bad "legacy pre-commit was not chained"; fi
if git -C "$TMP/repo" push -q -u origin feat/1-x; then ok; else bad "feature push should be allowed"; fi

git -C "$TMP/repo" checkout -q main
if git -C "$TMP/repo" commit -q --allow-empty -m nope; then
  bad "commit on main was allowed"
else
  ok
fi
git -C "$TMP/repo" checkout -q feat/1-x
if git -C "$TMP/repo" push -q origin HEAD:main; then
  bad "push to main was allowed"
else
  ok
fi

git -C "$TMP/repo" commit -q --allow-empty -m again
if git -C "$TMP/repo" push -q origin feat/1-x; then ok; else bad "fast-forward feature push should be allowed"; fi

# A same-second --amend of an identical empty commit can keep the same SHA.
git -C "$TMP/repo" commit -q --allow-empty --amend -m "amended"
if git -C "$TMP/repo" push -q --force origin feat/1-x; then
  bad "force-push was allowed"
else
  ok
fi
if git -C "$TMP/repo" push -q origin +feat/1-x; then
  bad "+refspec non-ff push was allowed"
else
  ok
fi

# Second install is idempotent.
"$INSTALL" --workdir "$TMP/repo" >/dev/null
if [[ "$(git -C "$TMP/repo" config --get core.hooksPath)" == ".relentless/githooks" ]]; then ok; else bad "hooksPath changed on reinstall"; fi

# Existing hooksPath (husky) is chained, not replaced.
git init -q -b main "$TMP/husky"
mkdir -p "$TMP/husky/.husky"
cat >"$TMP/husky/.husky/pre-commit" <<'EOF'
#!/bin/sh
echo husky >> "$(git rev-parse --git-dir)/husky-ran"
EOF
chmod +x "$TMP/husky/.husky/pre-commit"
printf '#!/bin/sh\necho husky-push >> "$(git rev-parse --git-dir)/husky-push"\n' >"$TMP/husky/.husky/pre-push"
chmod +x "$TMP/husky/.husky/pre-push"
git -C "$TMP/husky" config core.hooksPath .husky
git -C "$TMP/husky" commit -q --allow-empty -m init
"$INSTALL" --workdir "$TMP/husky" >/dev/null
"$INSTALL" --workdir "$TMP/husky" >/dev/null
if [[ "$(git -C "$TMP/husky" config --get core.hooksPath)" == ".husky" ]]; then ok; else bad "husky hooksPath was replaced"; fi
count="$(grep -c 'relentless:githooks' "$TMP/husky/.husky/pre-commit" || true)"
if [[ "$count" -eq 1 ]]; then ok; else bad "chain marker count=$count"; fi
if grep -q 'echo husky' "$TMP/husky/.husky/pre-commit"; then ok; else bad "husky body was clobbered"; fi

git -C "$TMP/husky" checkout -q -b feat/1-x
rm -f "$TMP/husky/.git/husky-ran"
git -C "$TMP/husky" commit -q --allow-empty -m feat
if [[ -f "$TMP/husky/.git/husky-ran" ]]; then ok; else bad "husky pre-commit did not run on the feature branch"; fi
git -C "$TMP/husky" checkout -q main
rm -f "$TMP/husky/.git/husky-ran"
if git -C "$TMP/husky" commit -q --allow-empty -m nope; then
  bad "husky repo allowed a commit on main"
else
  ok
fi
if [[ -f "$TMP/husky/.git/husky-ran" ]]; then
  bad "main commit should stop before the original husky body"
else
  ok
fi

echo "pass=$PASS fail=$FAIL"
[[ $FAIL -eq 0 ]]
