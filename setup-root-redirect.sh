#!/usr/bin/env bash
set -euo pipefail

# Root redirect setup for GitHub Pages user site.
# Publishes https://<user>.github.io/ -> https://<user>.github.io/blog/

GH_USER="yrong"
TARGET_URL="https://yrong.github.io/blog/"
REPO_NAME="${GH_USER}.github.io"
WORKDIR="${HOME}/tmp/${REPO_NAME}"

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: GitHub CLI 'gh' is required. Install from https://cli.github.com/"
  exit 1
fi

echo "Preparing ${REPO_NAME} in ${WORKDIR}"
rm -rf "${WORKDIR}"
mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

git init
git checkout -b main

cat > index.html <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta http-equiv="refresh" content="0; url=${TARGET_URL}">
  <link rel="canonical" href="${TARGET_URL}">
  <script>window.location.replace("${TARGET_URL}");</script>
  <title>Redirecting...</title>
</head>
<body>
  Redirecting to <a href="${TARGET_URL}">${TARGET_URL}</a>
</body>
</html>
EOF

cat > README.md <<EOF
# ${REPO_NAME}
Root redirect for GitHub Pages user site.
EOF

git add .
git commit -m "Add root redirect to blog"

if gh repo view "${GH_USER}/${REPO_NAME}" >/dev/null 2>&1; then
  echo "Repo exists: ${GH_USER}/${REPO_NAME}"
  if ! git remote get-url origin >/dev/null 2>&1; then
    git remote add origin "https://github.com/${GH_USER}/${REPO_NAME}.git"
  fi
  git push -u origin main
else
  gh repo create "${GH_USER}/${REPO_NAME}" --public --source=. --remote=origin --push
fi

# Enable Pages from main branch root; if already enabled, continue.
set +e
gh api \
  --method POST \
  -H "Accept: application/vnd.github+json" \
  "/repos/${GH_USER}/${REPO_NAME}/pages" \
  -f source[branch]=main \
  -f source[path]=/
PAGES_RC=$?
set -e

if [ "$PAGES_RC" -ne 0 ]; then
  echo "Pages may already be enabled. You can verify in repo settings."
fi

echo "Done. Check: https://${GH_USER}.github.io/"
