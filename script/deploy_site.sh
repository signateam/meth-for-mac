#!/usr/bin/env bash
# Deploys site/ to trymeth.com on Cloudflare.
# Needs CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID in the environment
set -euo pipefail
cd "$(dirname "$0")/.."

out=dist/site-deploy
rm -rf "$out"
mkdir -p "$out"
rsync -a --exclude README.md --exclude art/ --exclude .DS_Store site/ "$out/"

if [ ! -f "$out/download/Meth.dmg" ]; then
  echo "warning: site/download/Meth.dmg is missing; run ./script/release.sh first" >&2
fi

npx -y wrangler@4 deploy
