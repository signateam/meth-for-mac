# trymeth.com

The static site for Meth. There is no build step: everything in this folder is served as is.

| Path | What it is |
| --- | --- |
| `index.html` | Landing page. The Get Meth button links to `/download/Meth.dmg`. |
| `privacy.html`, `404.html` | Privacy notice and not-found page. |
| `download/Meth.dmg` | The notarized release, written by `script/release.sh`. |
| `appcast.xml` | Sparkle update feed (`SUFeedURL`), written by `script/release.sh`. |
| `_headers` | Response headers applied by Cloudflare (HSTS, DMG and appcast headers). |
| `robots.txt`, `sitemap.xml`, `favicon.svg`, `og.png` | The usual. `art/og.html` is the source for `og.png`. |

Preview locally:

```sh
python3 -m http.server 8000 --directory site
```

## Deploy

The site is live on Cloudflare as the Worker `trymeth` (static assets), with
`trymeth.com` and `www.trymeth.com` attached as custom domains in the Signa
Cloudflare account. `wrangler.jsonc` at the repo root holds the config.

```sh
export CLOUDFLARE_ACCOUNT_ID=<account id>
export CLOUDFLARE_API_TOKEN=<token that can deploy Workers>
./script/deploy_site.sh
```

`deploy_site.sh` copies `site/` into `dist/site-deploy` (leaving out this
README and `art/`) and runs `wrangler deploy`. The Worker (`worker/index.js`)
redirects `http://` and `www.` to `https://trymeth.com` and serves
`/api/visitors`, the recent-visitor count shown under the animation. That
endpoint reads Cloudflare Web Analytics with its own read-only token, stored
once as a Worker secret:

```sh
npx wrangler secret put CF_ANALYTICS_TOKEN   # a token with only Account Analytics Read
```

Without it the site still works and the count stays hidden. `_headers` applies to
the deployed files. Keep each file under 25 MiB, which is Cloudflare's asset limit.

## Cut a release

1. Bump `script/version.env`: `MARKETING_VERSION` (for example `1.0.1`) and `BUILD_NUMBER`. `BUILD_NUMBER` must go up every release, because Sparkle compares it.
2. Run `./script/release.sh` (optionally `./script/release.sh notes.md` to embed release notes). It builds and signs the app, notarizes and staples the app and the DMG, copies the DMG to `site/download/Meth.dmg` and regenerates `site/appcast.xml`. It needs the `meth-notary` notarytool profile once per Mac:

   ```sh
   xcrun notarytool store-credentials meth-notary --apple-id <apple id> --team-id Z9884J6ZQT
   ```

   Run that in a normal Terminal window, because it asks for an app-specific password.
3. Smoke-test the DMG: mount it, copy `Meth.app` to a temporary folder, run `spctl -a -vv` on it and open it.
4. Deploy with `./script/deploy_site.sh`, then commit `script/version.env`, `site/download/Meth.dmg` and `site/appcast.xml` together. Check that `https://trymeth.com/appcast.xml` shows the new version and that `https://trymeth.com/download/Meth.dmg` downloads it.

Always publish the DMG and the appcast together. The appcast entry is signed for that exact file, so a mismatched pair makes Sparkle reject the update.
