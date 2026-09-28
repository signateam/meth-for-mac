# trymeth.com

The static site for Meth. There is no build step: everything in this folder is served as is.

| Path | What it is |
| --- | --- |
| `index.html` | Landing page. The Get Meth button links to `/download/Meth.dmg`. |
| `privacy.html`, `404.html` | Privacy notice and not-found page. |
| `download/Meth.dmg` | The notarized release, written by `script/release.sh`. |
| `appcast.xml` | Sparkle update feed (`SUFeedURL`), written by `script/release.sh`. |
| `CNAME` | `trymeth.com`, for GitHub Pages. |
| `_headers` | Response headers for Cloudflare Pages. GitHub Pages ignores it. |
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
export CLOUDFLARE_ACCOUNT_ID=d801fe59adab888d7a28d3a7a7d181e4
export CLOUDFLARE_API_TOKEN="$(op read 'op://Signa Team Vault/pjtrp5rypgy3jsdys4ox5jtpnu/credential')"
./script/deploy_site.sh
```

`deploy_site.sh` copies `site/` into `dist/site-deploy` (leaving out this
README, `art/` and `CNAME`) and runs `wrangler deploy`. `_headers` applies to
the deployed files. Keep each file under 25 MiB, which is Cloudflare's asset limit.

## Cut a release

1. Bump `script/version.env`: `MARKETING_VERSION` (for example `1.0.1`) and `BUILD_NUMBER`. `BUILD_NUMBER` must go up every release, because Sparkle compares it.
2. Run `./script/release.sh` (optionally `./script/release.sh notes.md` to embed release notes). It builds and signs the app, notarizes and staples the app and the DMG, copies the DMG to `site/download/Meth.dmg` and regenerates `site/appcast.xml`. It needs the `meth-notary` notarytool profile once per Mac:

   ```sh
   xcrun notarytool store-credentials meth-notary --apple-id <apple id> --team-id Z9884J6ZQT
   ```

   Run that in a normal Terminal window, because it asks for an app-specific password.
3. Smoke-test the DMG: mount it, copy `Meth.app` to a temporary folder, run `spctl -a -vv` on it and open it.
4. Commit `script/version.env`, `site/download/Meth.dmg` and `site/appcast.xml` together, then push to `main`.
5. Deploy. GitHub Pages and Cloudflare Pages both deploy on the push. Check that `https://trymeth.com/appcast.xml` shows the new version and that `https://trymeth.com/download/Meth.dmg` downloads it.

Always publish the DMG and the appcast together. The appcast entry is signed for that exact file, so a mismatched pair makes Sparkle reject the update.
