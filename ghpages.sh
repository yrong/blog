
#!/bin/sh

set -e

DIR=$(dirname "$0")
cd "$DIR"

if [ -n "$(git status --porcelain)" ]
then
    echo "The working directory is dirty. Please commit any pending changes."
    exit 1
fi

echo "Deleting old publication"
rm -rf public
mkdir public
git worktree prune
rm -rf .git/worktrees/public/

echo "Checking out gh-pages branch into public"
git worktree add -B gh-pages public origin/gh-pages

echo "Removing existing files"
rm -rf public/*

echo "Generating site"
hugo

echo "Updating gh-pages branch"
cd public
git add --all

if git diff --cached --quiet
then
    echo "No changes to publish on gh-pages"
else
    git commit -m "Publishing to gh-pages (publish.sh)"
fi

echo "Pushing gh-pages branch"
git push origin gh-pages
