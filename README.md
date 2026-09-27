# Meth

Meth is a macOS 15+ menu bar app with three eye states:

- **Off:** Meth makes no sleep request.
- **Caffeine:** Meth prevents idle system sleep while allowing the display to dim. This is the launch default.
- **Meth:** Meth disables lid-close sleep. In this build, the built-in display stays on when the lid is shut. Meth stays on until you explicitly turn it off, including after reopening the lid.

Left-click the eye for the menu. Right-click to toggle Meth. Settings has a Mode choice for Off, Caffeine, or Meth, followed by Start at login and Caffeinate when Meth launches. The closed-lid setup button is hidden once its power permission and Meth Dealer are ready; it reappears if either needs repair.

## Install

1. Move `Meth.app` to `/Applications` and open it. The app has no Dock icon; look for the eye in the menu bar.
2. Open **Settings** and choose **Meth**, or use **Set Up Closed-Lid Mode** if it appears. Read the screen-on explanation, then approve the macOS administrator prompt. Setup installs two narrowly scoped `pmset` permissions and Meth Dealer, a user background process. Meth Dealer re-applies Meth after power-source changes and completes an explicit turn-off request if the menu app closes mid-transition. The setup button disappears when closed-lid mode is ready.
3. Choose a mode in Settings, or right-click the eye to toggle Meth. The pupil turns red only after macOS confirms the setting.

This is a local ad-hoc signed build. macOS may require you to use **Open** from Finder the first time. If you move the app after setup, use **Repair Closed-Lid Mode** from its new location so Meth Dealer points to it. Repair reuses the existing power permission without another administrator prompt when that permission remains active.

Meth uses a system-wide power setting for closed-lid mode. Other sleep-control apps can conflict with it. The setting may persist when the menu app is not running, so keep the app available and turn Meth off when you are done. The screen stays on when closed with Meth active; that is required for this build's closed-lid mode. It can consume battery and produce heat, so keep the Mac ventilated and out of a bag.

## Build

Run `./script/build_and_run.sh`. The script builds both executables, creates `dist/Meth.app`, signs it locally, and launches it. `./script/build_and_run.sh --verify` also checks that the menu app stays running. The Codex **Run** action uses this script.

## Remove closed-lid setup

Turn Meth off first. Remove `~/Library/LaunchAgents/com.toli.meth.dealer.plist` and unload its launch agent, then remove `/private/etc/sudoers.d/meth` with administrator approval. The app never removes the sleep override implicitly. Check that `SleepDisabled` is `No` before deleting the app.

## Implementation notes

- The menu bar app is a macOS agent app (`LSUIElement`) with an AppKit status item and a small Settings window.
- Caffeinate uses a process-owned `ProcessInfo` idle-sleep assertion.
- Closed-lid mode uses `pmset -a disablesleep 1` and `0`. The exact sudo commands are allowlisted by the setup script. This power setting is undocumented and must be checked on each supported macOS release.
- The companion process watches power-source notifications and also reconciles the requested and actual states every 15 seconds.
- The GitHub footer icon is from [Primer Octicons](https://github.com/primer/octicons) under its MIT license, included in the app resources.
