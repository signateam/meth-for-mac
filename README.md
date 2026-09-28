# Meth

Meth is a macOS 15+ menu bar app with three eye states:

- **Off:** Meth makes no sleep request.
- **Caffeine:** Meth prevents idle system sleep while allowing the display to dim. This is the launch default.
- **Meth:** Meth disables lid-close sleep. In this build, the built-in display stays on when the lid is shut. Meth stays on until you explicitly turn it off, including after reopening the lid.

Left-click the eye for the menu. Right-click to toggle Meth. Settings has a Mode choice for Off, Caffeine, or Meth, followed by Start at login, Caffeinate when Meth launches, and Turn off Meth at 10% battery. The closed-lid setup button is hidden once its power permission and Meth Dealer are ready; it reappears if either needs repair.

## Install

1. Move `Meth.app` to `/Applications` and open it. The app has no Dock icon; look for the eye in the menu bar.
2. Open **Settings** and choose **Meth**, or use **Set Up Closed-Lid Mode** if it appears. Read the screen-on explanation, then approve the macOS administrator prompt. Setup installs one sudo rule file, `/etc/sudoers.d/trymeth-<your short user name>`, that lets only your account run `pmset -a disablesleep 0` and `pmset -a disablesleep 1` without a password. It also registers Meth Dealer, a background process that appears under Meth in **System Settings > General > Login Items & Extensions**. If macOS asks you to allow it there, turn it on and choose **Repair Closed-Lid Mode**. Meth Dealer re-applies Meth after power-source changes and completes an explicit turn-off request if the menu app closes mid-transition. The setup button disappears when closed-lid mode is ready.
3. Choose a mode in Settings, or right-click the eye to toggle Meth. The pupil turns red only after macOS confirms the setting.

This is a local ad-hoc signed build. macOS may require you to use **Open** from Finder the first time. If you move the app after setup, open it from its new location and it points Meth Dealer there. If the app is moved to the Trash or deleted, Meth Dealer restores normal sleep and removes itself. Repair reuses the existing power permission without another administrator prompt when that permission remains active.

Meth uses a system-wide power setting for closed-lid mode. Other sleep-control apps can conflict with it. The setting may persist when the menu app is not running, so keep the app available and turn Meth off when you are done. The screen stays on when closed with Meth active; that is required for this build's closed-lid mode. It can consume battery and produce heat, so keep the Mac ventilated and out of a bag.

Meth has two safety cutoffs. On battery power at 10% or less, Meth turns itself off and restores normal sleep; you can turn this off in Settings with **Turn off Meth at 10% battery**. If macOS reports a critical thermal state, Meth always turns itself off. Meth Dealer checks both every 15 seconds and on power-source and thermal changes, and the menu shows why, for example “Meth turned off: battery at 10%”. Meth also refuses to turn on while either cutoff applies.

## Build

Run `./script/build_and_run.sh`. The script builds both executables, creates `dist/Meth.app`, signs it locally, and launches it. `./script/build_and_run.sh --verify` also checks that the menu app stays running. The Codex **Run** action uses this script.

`./script/bundle.sh` assembles the app without launching it. It takes `--configuration debug|release` (default debug), `--arch ARCH` (repeatable; release defaults to a universal arm64 + x86_64 build) and `--sign IDENTITY` (default ad-hoc). A Developer ID identity signs with the hardened runtime and a secure timestamp. The version comes from `script/version.env`.

## Updates

Meth updates itself with [Sparkle 2](https://sparkle-project.org), a SwiftPM dependency. `bundle.sh` copies `Sparkle.framework` into `Contents/Frameworks` and writes `SUFeedURL` (`https://trymeth.com/appcast.xml`), `SUPublicEDKey` and `SUEnableAutomaticChecks` into `Info.plist`. With a Developer ID identity it signs Sparkle's `Autoupdate`, `Updater.app` and XPC services, then the framework, the dealer and the app, each with `--options runtime --timestamp` and never `--deep`. The menu has **Check for Updates…**.

The EdDSA update key was made with Sparkle's `generate_keys`. Its private half lives in the login keychain (account `ed25519`); back it up with `.build/artifacts/sparkle/Sparkle/bin/generate_keys -x <file>` and keep that file private. Only the public key is in `bundle.sh`.

To publish a release: bump `script/version.env`, then run `./script/release.sh [notes.html]`. It builds the universal bundle signed with the Developer ID identity, checks it with `codesign` and `spctl`, notarizes and staples the app (as a `ditto` zip), builds `dist/Meth.dmg` (UDZO, `Meth.app` plus an `/Applications` link), then signs, notarizes and staples the DMG. It copies the DMG to `site/download/Meth.dmg` and runs `./script/make_appcast.sh`, which writes `site/appcast.xml` with one signed entry for `https://trymeth.com/download/Meth.dmg`. If notarization fails it prints the `notarytool log`. It needs the `meth-notary` notarytool profile, stored once from an interactive terminal with `xcrun notarytool store-credentials meth-notary --apple-id <apple id> --team-id Z9884J6ZQT`. It exports the Sparkle key to a private temporary file that it deletes on exit, so macOS does not prompt for keychain access. Deploy the site with the DMG and the feed together, since the feed's signature and length describe that exact file.

## Remove closed-lid setup

Open **Settings** and choose **Uninstall Closed-Lid Mode**. After you confirm, Meth turns Meth off and restores normal sleep, unregisters Meth Dealer, and asks for an administrator password once to remove `/etc/sudoers.d/trymeth-<your short user name>`. It also removes an older `/etc/sudoers.d/meth` file if that file holds your account's Meth rule. It never removes another account's rule. Meth stays usable for Caffeine, and you can set up closed-lid mode again later.

To remove it by hand, turn Meth off, run `sudo pmset -a disablesleep 0`, turn off Meth under Login Items & Extensions, then delete the sudo rule file with `sudo rm /etc/sudoers.d/trymeth-<your short user name>`. Check that `pmset -g | grep SleepDisabled` shows `0` before deleting the app.

## Implementation notes

- The menu bar app is a macOS agent app (`LSUIElement`) with an AppKit status item and a small Settings window.
- Caffeinate uses a process-owned `ProcessInfo` idle-sleep assertion.
- Closed-lid mode uses `pmset -a disablesleep 1` and `0`. The exact sudo commands are allowlisted per user. The privileged setup script is compiled into the signed app (`PowerAccessScript.swift`) and passed as text to the administrator prompt, so no file in the app bundle runs as root. It checks the rule with `visudo -cf` and installs it atomically as `root:wheel 0440`. This power setting is undocumented and must be checked on each supported macOS release.
- Meth Dealer is registered with `SMAppService.agent(plistName:)` from `Contents/Library/LaunchAgents/com.toli.trymeth.dealer.plist`, which uses `BundleProgram`.
- The companion process watches power-source and thermal-state notifications and also reconciles the requested and actual states every 15 seconds. Battery level comes from `IOPSCopyPowerSourcesInfo`; the cutoff logic is in `Sources/MethShared/SafetyCutoff.swift`.
- Meth 1.0 uses the `com.toli.trymeth` identifier. On launch it copies settings from the old `com.toli.meth.shared` domain if the new one is empty, and replaces an old `~/Library/LaunchAgents/com.toli.meth.dealer.plist` agent with the new Meth Dealer. The older `/etc/sudoers.d/meth` rule keeps working until closed-lid setup is repaired, which replaces it with the per-user file.
- The GitHub footer icon is from [Primer Octicons](https://github.com/primer/octicons) under its MIT license, included in the app resources.
