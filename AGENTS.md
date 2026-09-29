# AGENTS.md

Guidance for coding agents working in this repo. Read `README.md` for what Meth is and how users install it.

## What's here

- **Meth.app**: a macOS 15+ menu bar app (Swift, SwiftPM, AppKit, no Xcode project) with three modes: Off, Caffeine and Meth (closed-lid mode). Bundle ID `com.toli.trymeth`.
- **trymeth.com**: a static site in `site/`, served by a Cloudflare Worker (`worker/index.js`, `wrangler.jsonc`).
- **Marketing sources**: `concepts/` (comparison images) and `site/art/` (OG image and vein generators).

| Path | What |
| --- | --- |
| `Sources/Meth` | Menu bar app: status item, menu, Settings, closed-lid setup (`PowerAccessSetup.swift`, `PowerAccessScript.swift`) |
| `Sources/MethDealer` | Background helper (`SMAppService` LaunchAgent `com.toli.trymeth.dealer`). Re-applies Meth, enforces safety cutoffs, restores sleep if the app is removed |
| `Sources/MethShared` | Preferences, `pmset` control (`PowerTool.swift`), battery and thermal cutoffs (`SafetyCutoff.swift`) |
| `script/` | `build_and_run.sh`, `bundle.sh`, `release.sh`, `make_appcast.sh`, `deploy_site.sh`; `script/dmg/` holds the install window |
| `site/` | Landing, privacy and 404 pages, `download/Meth.dmg`, `appcast.xml`, `_headers` |
| `worker/` | HTTPS redirect, static assets, `/api/visitors` (recent visits + download total), `/api/email-link` |

## Build and check

```sh
swift build                                   # must stay warning-free
./script/bundle.sh --configuration debug      # dist/Meth.app, ad-hoc signed, not launched
./script/build_and_run.sh                     # builds and LAUNCHES the app (see safety rules)
node --check worker/index.js                  # after any Worker change
```

There is no test target. Verify logic with small throwaway Swift scripts, and verify UI by rendering.

## Safety rules

- **Do not run the closed-lid setup or anything that needs an administrator password.** The only sudo command you may run is the allowlisted `sudo -n /usr/bin/pmset -a disablesleep 0` (to restore normal sleep). Never run `disablesleep 1`.
- **Don't launch Meth without a reason.** Launching migrates settings, registers the dealer and can change the owner's power state. Build with `bundle.sh` instead of `build_and_run.sh` when you only need the bundle, and `pkill -x Meth` afterwards if you did launch it.
- Never edit `/etc/sudoers.d/*` or `~/Library/LaunchAgents` by hand.
- The ownership rule: Meth only records `methOwnsOverride` after macOS confirms the change (`PowerTool.setSleepDisabled` polls for up to 2 s), and only clears it after sleep is confirmed restored. Keep every path consistent with that. It prevents `SleepDisabled=1` from being orphaned.
- **This repo is public.** Never commit tokens, keys, `.p12` files, the Sparkle private key, password-manager item names or IDs, or other internal identifiers. Secrets live in the owner's keychain, the team password manager and Worker secrets.

## Git

- **Check the branch first.** Other agents (for example Codex) sometimes work in this same checkout and leave it on another branch. Run `git branch --show-current` before committing. For work on another branch, use `git worktree add --detach /private/tmp/<name> origin/<branch>` and push with `git push origin HEAD:<branch>`.
- Commit with a public identity (`Toli Marchuk <tolimarchuk@users.noreply.github.com>`, set in the repo config).
- Commit or push only when asked.
- Keep commits focused. Commit only the files you changed, since another agent may have unrelated edits in progress.

## Releasing the app

1. Bump `script/version.env`. `BUILD_NUMBER` must increase every release, because Sparkle compares it.
2. `./script/release.sh` does the following:
   - builds a universal (arm64 + x86_64) app with `lipo`, because the Command Line Tools can't build multi-arch in one step
   - signs it inside out with the Developer ID identity (team `Z9884J6ZQT`), hardened runtime and timestamps, including Sparkle's nested code
   - notarizes and staples the app
   - builds the styled DMG with dmgbuild, then notarizes and staples it
   - writes `site/download/Meth.dmg` and a signed `site/appcast.xml`

   It needs the `meth-notary` notarytool keychain profile, dmgbuild (`/usr/bin/python3 -m pip install --user dmgbuild`) and the Sparkle EdDSA key in the login keychain. Notarization can take minutes, so run it in the background and poll.
3. Deploy the DMG and the appcast together. The appcast signature and length describe that exact file.

## Deploying the site

```sh
export CLOUDFLARE_ACCOUNT_ID=... CLOUDFLARE_API_TOKEN=...   # a token that can deploy Workers
./script/deploy_site.sh                                     # stages site/ into dist/site-deploy, runs wrangler deploy
```

- The Worker runs before the static assets (`run_worker_first`). It redirects `http://` and `www.` to `https://trymeth.com`.
- It counts complete `GET /download/Meth.dmg` downloads in a Durable Object (`DownloadCounter`, seeded by `DOWNLOADS_SEED`).
- It serves `/api/visitors`: recent visits from Cloudflare Web Analytics, cached for 60 s at the edge and `no-store` for browsers, plus the download total.
- It serves `/api/email-link`: the download link emailed through Cloudflare Email Service. This is gated by `EMAIL_LINK_ENABLED`, Turnstile, a honeypot, an Origin check and a rate limit.
- Worker secrets, set once with `wrangler secret put`: `CF_ANALYTICS_TOKEN` (read-only analytics) and `TURNSTILE_SECRET`.
- Browsers and social sites cache aggressively. When `og.png` changes, bump the `?v=` on the `og:image` and `twitter:image` URLs in `site/index.html`.
- After deploying, verify with `curl --resolve trymeth.com:443:104.21.11.94 ...` if local DNS is stale.

## Working on the site

- `site/index.html` is a single hand-tuned file: CSS, markup and script together, with no build step and no frameworks. Keep it that way, and match its style.
- **Themes.** Light and dark come from CSS tokens on `:root`. An inline head script sets `data-theme` from `localStorage` or the system setting. The terminal card has its own theme-scoped variables.
- **The hero animation** is a CSS 3D MacBook driven by `requestAnimationFrame`.
  - The ajar lid angle (about −164°) is deliberately below the camera's view angle, so the swing never turns it edge-on.
  - The cursor sequence mirrors the app's real menu (Off / Caffeine / Meth).
- **Generated art.**
  - `site/art/veins.mjs` and `pill-veins.mjs` write the bloodshot vein SVGs into `index.html`: `node site/art/veins.mjs site/index.html 23` and `node site/art/pill-veins.mjs site/index.html 9`.
  - `site/art/og.html` renders `site/og.png`.
  - `script/dmg/veins.mjs` and `render_background.sh` produce the DMG window background.
- **Copy direction from the owner:** "Meth for your Mac." Straight to the point, not corny. No drug imagery beyond the brand's eye, red veins and blue gem.
- **Mobile.** On phones, the hero is centred, "Try Meth" opens the email-link form, and the email option replaces the share link. Desktop never shows the email option.

## Rendering and screenshots

Use headless Chrome: `"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars --virtual-time-budget=1500 --window-size=W,H --screenshot=OUT file://...`

- Headless mode doesn't run `requestAnimationFrame` or CSS transitions. To capture a state of the card, make a copy and stub things out. Set `window.requestAnimationFrame=()=>0`, stub `IntersectionObserver`, and replace `setPhase(reduce ? 1 : 0);` with `setPhase(0)` or `setPhase(1)`. Stub `fetch` for the API-driven lines.
- The minimum window width is about 500px. For a 390px phone view, wrap the page in an iframe inside a wider window, with `--allow-file-access-from-files`.
- The default colour scheme follows the machine. Pass `--blink-settings=preferredColorScheme=1` for light or `0` for dark.
- macOS has no `timeout` command. `sips -c H W --cropOffset Y X` crops in place unless you pass `--out`.
- Look at every render before calling UI work done.
