# Meth

**This repo is public.** Never commit tokens, keys, `.p12` files, the Sparkle private key, password-manager item names or IDs, account IDs, client names or other internal identifiers. Secrets live in the owner's keychain, the team password manager and Worker secrets. Pushing publishes, so commit or push only when Toli asks.

- **Meth.app**: macOS 15+ menu bar app (Swift, SwiftPM, AppKit, no Xcode project) with three modes: Off, Caffeine, Meth (closed-lid). Bundle ID `com.toli.trymeth`. `README.md` covers what it is and how users install it.
- `Sources/Meth`: menu bar app and closed-lid setup (`PowerAccessSetup.swift`, `PowerAccessScript.swift`). `Sources/MethDealer`: background helper (`SMAppService` LaunchAgent `com.toli.trymeth.dealer`) that re-applies Meth, enforces safety cutoffs and restores sleep if the app is removed. `Sources/MethShared`: preferences, `pmset` control (`PowerTool.swift`), battery and thermal cutoffs (`SafetyCutoff.swift`).
- **trymeth.com**: static `site/` served by a Cloudflare Worker (`worker/index.js`, `wrangler.jsonc`). Marketing art sources: `concepts/`, `site/art/`.

## Power-state safety
- Never run the closed-lid setup or anything that needs an administrator password. The only sudo you may run is the allowlisted `sudo -n /usr/bin/pmset -a disablesleep 0` (restores normal sleep). Never run `disablesleep 1`.
- Don't launch Meth without a reason: launching migrates settings, registers the dealer and can change the owner's power state. Use `bundle.sh` when you only need the bundle, and `pkill -x Meth` afterwards if you did launch it.
- Never hand-edit `/etc/sudoers.d/*` or `~/Library/LaunchAgents`.
- Ownership rule: Meth records `methOwnsOverride` only after macOS confirms the change (`PowerTool.setSleepDisabled` polls up to 2 s) and clears it only after sleep is confirmed restored, so `SleepDisabled=1` is never orphaned. Keep every path consistent with it.

## Build and check
```sh
swift build                                   # must stay warning-free
./script/bundle.sh --configuration debug      # dist/Meth.app, ad-hoc signed, not launched
./script/build_and_run.sh                     # builds and LAUNCHES the app (see safety rules)
node --check worker/index.js                  # after any Worker change
```
No test target: test logic with small throwaway Swift scripts and check UI by rendering.

## Git
- Other agents share this checkout and may leave it on another branch. Run `git branch --show-current` before committing; for work on another branch use `git worktree add --detach /private/tmp/<name> origin/<branch>` and `git push origin HEAD:<branch>`.
- Commit identity is the public `Toli Marchuk <tolimarchuk@users.noreply.github.com>` (set in the repo config).

## Release the app
1. Bump `script/version.env`. `BUILD_NUMBER` must increase every release, because Sparkle compares it.
2. `./script/release.sh` builds a universal app with `lipo` (the Command Line Tools can't build multi-arch in one step), signs inside out with Developer ID (team `Z9884J6ZQT`, hardened runtime, timestamps, Sparkle's nested code), notarizes and staples the app and the dmgbuild DMG, and writes `site/download/Meth.dmg` plus a signed `site/appcast.xml`. It needs the `meth-notary` notarytool keychain profile (check with `xcrun notarytool history --keychain-profile meth-notary`), dmgbuild (`/usr/bin/python3 -m pip install --user dmgbuild`) and the Sparkle EdDSA key in the login keychain. Notarization can take minutes (the first took about 25): run it in the background and poll.
3. Deploy the DMG and the appcast together. The appcast signature and length describe that exact file.

## Site
- Deploy: `CLOUDFLARE_ACCOUNT_ID=... CLOUDFLARE_API_TOKEN=... ./script/deploy_site.sh` (stages `site/` into `dist/site-deploy`, runs `wrangler deploy`). The Workers deploy token has no DNS permission on trymeth.com; DNS and Email Service changes go through Cloudflare's `cf` CLI.
- The Worker (`worker/index.js`) runs before static assets (`run_worker_first`): HTTPS and `www` redirects, the download counter (Durable Object `DownloadCounter`, seeded by `DOWNLOADS_SEED`), `/api/visitors` and `/api/email-link` (gated by `EMAIL_LINK_ENABLED`, Turnstile, a honeypot, an Origin check and a rate limit). Worker secrets, set once with `wrangler secret put`: `CF_ANALYTICS_TOKEN` (read-only analytics) and `TURNSTILE_SECRET`.
- When `og.png` changes, bump `?v=` on the `og:image` and `twitter:image` URLs in `site/index.html`. If local DNS is stale after a deploy: `curl --resolve trymeth.com:443:104.21.11.94 ...`.
- `site/index.html` is one hand-tuned file (CSS, markup and script, no build step, no framework). Keep it that way and match its style. Light and dark come from `:root` tokens; an inline head script sets `data-theme` from `localStorage` or the system setting; the terminal card has its own theme-scoped variables.
- Hero: a CSS 3D MacBook on `requestAnimationFrame`. The ajar lid (about -164°) sits below the camera angle on purpose so the swing never turns it edge-on; the cursor sequence mirrors the real menu (Off / Caffeine / Meth).
- Generated art: `node site/art/veins.mjs site/index.html 23` and `node site/art/pill-veins.mjs site/index.html 9` write the vein SVGs; `site/art/og.html` renders `site/og.png`; `script/dmg/veins.mjs` and `render_background.sh` make the DMG background.
- Copy direction from the owner: "Meth for your Mac." Straight to the point, not corny. No drug imagery beyond the brand's eye, red veins and blue gem.
- Mobile: the hero is centred, "Try Meth" opens the email-link form, and the email option replaces the share link. Desktop never shows the email option.

## Rendering and screenshots
- `"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars --virtual-time-budget=1500 --window-size=W,H --screenshot=OUT file://...`
- Headless runs no `requestAnimationFrame` or CSS transitions. To capture a card state, render a copy with `window.requestAnimationFrame=()=>0`, stubbed `IntersectionObserver` and `fetch`, and `setPhase(reduce ? 1 : 0);` replaced by `setPhase(0)` or `setPhase(1)`.
- The minimum window width is about 500px; for a 390px phone view, wrap the page in an iframe inside a wider window with `--allow-file-access-from-files`. The colour scheme follows the machine: `--blink-settings=preferredColorScheme=1` is light, `0` dark.
- macOS has no `timeout` command. `sips -c H W --cropOffset Y X` crops in place unless you pass `--out`.
