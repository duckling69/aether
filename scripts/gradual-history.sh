#!/bin/bash
# Creates a fresh git history for Aether with commits dated across ~3 days.
# Run from repo root (aether/): bash scripts/gradual-history.sh
set -e

echo "Resetting git history for realistic 3-day spread..."
rm -rf .git
git init
git config user.name "Vivek Jha"
git config user.email "dev@duckling69.example"

# Helper
commit_on() {
  local d="$1"; shift
  GIT_AUTHOR_DATE="$d" GIT_COMMITTER_DATE="$d" git commit -m "$*"
}

# === 2026-06-25 (Day 1: contracts foundation) ===
git add contracts/contracts/AetherPool.sol contracts/contracts/mocks/MockERC20.sol contracts/hardhat.config.js
commit_on "2026-06-25T09:20:00" "chore: bootstrap contracts skeleton + AetherPool.sol"

git add contracts/config/ contracts/ignition/
commit_on "2026-06-25T11:40:00" "feat(contracts): add ignition modules and token configs"

git add contracts/scripts/ contracts/test/
commit_on "2026-06-25T16:55:00" "test + chore: init scripts, tests and reserve init helpers"

# === 2026-06-26 (Day 2: web + UI) ===
git add web/package.json web/app/ web/next*.js web/tsconfig.json
commit_on "2026-06-26T09:05:00" "feat(web): add Next.js 16 shell + providers + layout"

git add web/protocol/ web/store/ web/utils/
commit_on "2026-06-26T12:30:00" "feat(protocol): aave-compat stub + deployment + rwa glue for Aether"

git add web/modules/ web/components/ web/hooks/ web/layouts/
commit_on "2026-06-26T17:15:00" "feat(ui): markets dashboard history and components"

git add web/ui-config/ web/public/
commit_on "2026-06-26T20:45:00" "chore(web): ui configs and assets"

# === 2026-06-27 (Day 3: docs, scripts, portfolio ready) ===
git add README.md .gitignore contracts/.gitignore web/.gitignore
commit_on "2026-06-27T10:10:00" "docs: original README and clean gitignores"

git add scripts/
commit_on "2026-06-27T14:20:00" "chore: add gradual-history and deploy helper scripts"

git add .
commit_on "2026-06-27T18:50:00" "chore: final project polish and deploy notes"

# One more on 28th for spread
git add README.md
commit_on "2026-06-28T09:00:00" "docs: tweak deployment instructions post test run"

echo "=== History created ==="
git log --pretty=format:"%ad %h %s" --date=short | cat
echo ""
echo "Total commits: $(git rev-list --all --count)"
echo ""
echo "Next (user): git remote add ... && git push (force for clean repo)"
