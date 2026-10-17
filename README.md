# EarPods Inline Button Probe

This repo contains a small Swift command-line probe for discovering how wired Apple EarPods inline buttons surface on macOS.

It also now includes `earpods-launcher`, a hidden Mac-style command HUD controlled by the EarPods buttons.

## Commands

```bash
swift run earpods-probe --mode hid --log-path ./logs/earpods-events.ndjson
```

Or, after building once:

```bash
./.build/debug/earpods-probe --mode hid --log-path ./logs/earpods-events.ndjson
```

Enable gesture notifications plus an optional action config:

```bash
./.build/debug/earpods-probe \
  --mode hid \
  --log-path ./logs/earpods-events.ndjson \
  --actions-path ./config/actions.example.json
```

Try exclusive HID capture if you want the probe to attempt to stop macOS from handling the EarPods buttons itself:

```bash
./.build/debug/earpods-probe \
  --mode hid \
  --log-path ./logs/earpods-events.ndjson \
  --actions-path ./config/actions.example.json \
  --seize
```

Run the secret launcher HUD:

```bash
./.build/debug/earpods-launcher \
  --config ./config/launcher.example.json \
  --log-path ./logs/launcher-events.ndjson \
  --idle-timeout-ms 5000
```

Build the no-terminal app bundle:

```bash
./scripts/build-launcher-app.sh
```

That produces:

```text
dist/Inlay.app
```

## Beta Install

For beta testing, `Inlay.app` can be shared directly as a downloadable app bundle or zip.

See [BETA_GUIDE.md](/Users/samyanmangat/Downloads/HeadphoneProject/BETA_GUIDE.md) for a tester-focused setup, recovery, and feedback checklist.

- macOS will likely warn that the app is from an unidentified developer because it is not signed or notarized yet
- testers can still open it by right-clicking the app, choosing `Open`, then confirming `Open` again
- if macOS still blocks it, go to `System Settings -> Privacy & Security` and choose `Open Anyway`
- first launch will walk through launcher setup, then Cipher setup
- launching `Inlay` again while it is already running should wake the existing hidden instance instead of starting a second copy

If HID mode prints nothing while button presses still affect the system, try the fallback:

```bash
swift run earpods-probe --mode system --log-path ./logs/earpods-system-events.ndjson
```

If HID mode fails with a permission error inside Codex or another sandboxed environment, run the built binary directly from a normal Terminal session.

## What It Logs

Each line in the NDJSON log contains:

- `timestamp`
- `recordType`
- `mode`
- `product`
- `transport`
- `vendorID`
- `productID`
- `registryID`
- `usagePage`
- `usage`
- `integerValue`
- `phase`
- `eventName`
- `gesture`
- `rawData1`
- `rawSubtype`
- `note`

`recordType` is `raw` for direct HID/system observations and `gesture` for the higher-level actions the tool derives, such as `center_double` or `center_hold`.

## Gestures

In HID mode the probe now recognizes:

- `volume_up`
- `volume_up_double`
- `volume_up_triple`
- `volume_down`
- `volume_down_double`
- `volume_down_triple`
- `volume_up_hold`
- `volume_down_hold`
- `center_single`
- `center_double`
- `center_triple`
- `center_hold`

Notifications are enabled by default. Use `--no-notify` if you only want console output and NDJSON logs.

## Launcher HUD

`earpods-launcher` is a background accessory app with a Mac-style floating HUD panel:

- `center_hold` opens the HUD
- `volume_up` moves selection up
- `volume_down` moves selection down
- `center_single` confirms the selected row
- `center_hold` closes the HUD if it is already open

The app bundle version uses these runtime paths:

- config: `~/Library/Application Support/EarPodsLauncher/launcher.json`
- logs: `~/Library/Logs/EarPodsLauncher/launcher-events.ndjson`
- onboarding state: `~/Library/Application Support/EarPodsLauncher/onboarding-state.json`
- cipher config: `~/Library/Application Support/EarPodsLauncher/cipher-config.json`
- work queue: `~/Library/Application Support/EarPodsLauncher/work-queue.json`
- companion config: `~/Library/Application Support/EarPodsLauncher/companion-config.json`

Those internal storage paths still use `EarPodsLauncher` for compatibility, even though the visible app name is now `Inlay`.

On first launch, the app copies the bundled example config into Application Support if `launcher.json` does not exist yet.

When the bundled app launches successfully, it shows a startup setup overlay. You must complete `+`, `-`, and a quick center tap, then finish with a center hold before setup will dismiss and the launcher goes silent in the background.

After the launcher setup completes on first run, the app also asks you to define a 4-step Cipher unlock code using `+`, `-`, `center tap`, or `center double`. You repeat it once to confirm, then hold center to save it. During Cipher setup:

- `volume_down_hold` clears the in-progress code
- in first-run setup, `center_hold` only saves once confirmation is complete
- in Cipher `Rekey`, `center_hold` cancels early and keeps your current code, or saves once the new code is confirmed

The launcher also supports contextual page onboarding. The first page using it is `Timer`:

- the first time you select `Timer`, a page-specific training overlay appears
- it teaches `+`, `-`, `center tap`, `center double`, and `center hold` in their Timer meanings
- you must prove those gestures before the Timer route is allowed to continue
- completion is remembered in `onboarding-state.json`, so it only appears once per page by default

`Timer` is now a real page instead of a placeholder selection:

- setup mode shows editable `Hours`, `Minutes`, and `Seconds` rows
- `+` and `-` adjust the selected row
- `center tap` moves forward, and tapping from `Seconds` starts the timer
- `center double` moves back one row
- `center hold` returns to the main launcher
- while the timer is running or paused, `+` and `-` add or subtract one minute
- while the timer is running, `center tap` pauses and `center double` cancels back to setup
- while the timer is paused, `center tap` resumes and `center double` cancels back to setup
- when the timer finishes, the app plays beeps and shows a notification

Configured rows stay in file order, and the launcher adds these built-in rows:

- `Companion`
- `Support`
- `Current Thread`
- `Work Queue`
- `Quit Inlay`

Most configured rows are still placeholder actions. Confirming one appends a structured `LAUNCH item=...` record to the NDJSON log and, in app mode, shows a short native notification such as `Selected Notes`.

`Companion` is now a real voice route:

- selecting `Companion` opens an interactive HUD with a text field for debugging
- type a short request and press Return, or hold center to speak and release to send
- try requests like `continue`, `open work queue`, `open current thread`, `open Safari`, `search github`, `what's playing`, or `set a timer for 20 minutes`
- Companion transcribes the request, then routes it with a local parser stack:
- by default it uses lightweight on-device semantic matching through Apple `NaturalLanguage`
- if a local Ollama server is running, it can also use a true local LLM for intent routing before falling back to the built-in semantic parser
- while speech is live, partial transcript text now appears in the HUD so you can see what the recognizer is hearing before it acts
- successful requests are remembered locally, so Companion gradually adapts to the phrases you actually use
- when it is unsure, it now suggests the closest supported requests instead of just failing cold
- choosing a fallback or saying `teach this as ...` now teaches Companion visibly in the card instead of only learning silently in the background
- timer durations are still extracted with a tiny local parser so requests like `set a timer for 20 minutes` remain reliable
- Companion can now explicitly target built-in portal surfaces, arbitrary apps by name, and fresh browser search tabs by query
- Companion does not reliably switch existing browser tabs yet; browser-style requests are treated as fresh search-tab opens
- Cipher can now teach Companion two personal layers:
- `ritual phrases`, which act as exact private shortcuts for portal actions like `Continue` or `Open Work Queue`
- `app meanings`, which let a noun like `canvas` or `design` resolve to a specific app before the normal semantic parser guesses
- `center_hold` closes Companion while it is idle, and hold-to-speak owns the center hold gesture while you are talking
- if macOS shows a microphone or speech permission prompt, approve it, then hold center again to begin live listening

Optional true local-LLM Companion config:

```json
{
  "ollamaBaseURL": "http://127.0.0.1:11434",
  "ollamaModel": "llama3.2:3b"
}
```

- save that in `~/Library/Application Support/EarPodsLauncher/companion-config.json`
- if `ollamaModel` is omitted, Companion will try to discover the first installed Ollama model automatically
- if Ollama is unavailable, Companion falls back to the built-in on-device semantic parser

`Work Queue` is now real:

- capture still exists inside `Work Queue` and through `Companion`, using the last real foreground app instead of Inlay itself
- captures now reuse the same local context-naming engine as `Current Thread`, so queue items feel more like named threads than raw app names
- `Work Queue` opens a private stack with the current thread kept on top and the backlog underneath
- queue items can now carry labels like `Important`, `Follow Up`, `Later`, and `Blocked`
- selecting a saved item now includes `Label Thread`, which opens a dedicated label picker without bloating the main action list
- labeled threads now show their label directly in the queue so you can scan the stack at a glance
- inside `Work Queue`, `+` and `-` move immediately, quick center tap confirms, and `center_hold` returns to the launcher
- selecting a saved item opens actions like `Resume App`, `Bump to Top`, `Archive`, `Delete`, and `Back`
- `Resume App` now also bumps that thread back to the top of the queue
- `center_double` returns from item detail back to the queue list, quick-removes the selected item when you are on the queue list itself, and steps back out of the label picker to thread actions

`Current Thread` is now a real page:

- selecting `Current Thread` opens a named snapshot of the app and focused window you’re actually in
- it uses a local context-naming engine to turn raw app/window context into a cleaner thread title
- the card shows a thread badge, a named title, quiet metadata, and actions for `Save to Queue`, `Resume App`, `Refresh Name`, and `Back`
- `Save to Queue` stages that named thread into `Work Queue`

`Support` is now a real page for beta setup and recovery:

- it shows live speech, microphone, and accessibility status
- it explains the current browser limitation clearly: Companion opens fresh search tabs, not existing tabs
- it points out that browser/Finder/music automation prompts happen on first use
- it explains that launching `Inlay` again should wake the existing instance if the app feels hidden
- it includes rows for `Open Speech Settings`, `Open Microphone Settings`, `Open Accessibility Settings`, `Open Companion Help`, `Restart Inlay`, `Reveal Logs`, `Reveal Support Files`, and `Back`

`Now Playing` is now a real mini card instead of a placeholder launch:

- selecting `Now Playing` opens a floating media card
- `volume_up` and `volume_down` move between card actions immediately
- quick center tap runs the highlighted action without closing the card
- `center_hold` or the visible `Back` row returns to the main launcher

Source resolution prefers Spotify when it has the active or paused current track, otherwise falls back to Music, then to the frontmost supported browser media tab. Browser detection is currently scoped to the active tab of the frontmost supported browser and is best for obvious media pages like YouTube. If none of those sources expose active media, the card shows an empty state with `Open Spotify`, `Open Music`, and `Back`.

The card currently includes:

- track title, artist, album
- source badge and player state
- a continuous listening-session timer
- Spotify actions: `Open in Spotify`, `Play/Pause`, `Copy Spotify Link`, `Back`
- Music actions: `Open in Music`, `Play/Pause`, `Back`
- Browser media actions: `Open in Browser`, `Back`

Session time is a single continuous listening stretch. It pauses when playback pauses and resets after roughly 5 minutes of inactivity.

## Cipher

Cipher is a hidden spell HUD and does not appear as a normal launcher row.

- while the portal is fully hidden, enter your saved 4-step Cipher code to open it
- a successful hidden unlock now shows a tiny transient `Cipher Unlocked` pulse before the Cipher HUD appears
- Cipher includes `Veil`, `Echo`, `Seal`, `Lexicon`, `Rekey`, and `Back`
- `Lexicon` is the new private language layer for Companion:
- teach exact ritual phrases for actions like `Continue`, `Work Queue`, `Current Thread`, `Timer`, `Now Playing`, and `Capture`
- teach personal noun-to-app meanings so Companion can reinterpret short phrases the way you do
- inside Lexicon, `+` and `-` move, center tap teaches the selected entry, typed Return saves, and `center_hold` returns you to Cipher
- `Rekey` reopens the Cipher setup overlay from inside Cipher so you can change your hidden code without deleting any files

The launcher always requests exclusive HID access, so the system volume overlay should stay out of the way while it is running.

Example launcher config: [launcher.example.json](/Users/samyanmangat/Downloads/HeadphoneProject/config/launcher.example.json)

## Action Config

`--actions-path` accepts a JSON object keyed by gesture name. Each gesture can override notification text and optionally run a shell command.

Example file: [actions.example.json](/Users/samyanmangat/Downloads/HeadphoneProject/config/actions.example.json)

Supported keys per gesture:

- `notifyTitle`
- `notifyBody`
- `notificationsEnabled`
- `shellCommand`

## True Unbind

The probe can now optionally request exclusive HID access with `--seize`. If macOS allows the seizure, the built-in volume and playback behavior may stop while the tool keeps receiving the raw EarPods events.

If `--seize` still leaves the system volume overlay active, the remaining fallback is Karabiner-Elements. Apple’s documented `hidutil` / `IOHIDEventSystemClient` remapping path is for keyboard services, while the EarPods are showing up as a consumer-control HID device on usage page 12.

If you want to truly suppress the default volume behavior, the practical route is Karabiner-Elements. I added a ready-to-test rule file here:

- [karabiner-earpods-unbind-volume.json](/Users/samyanmangat/Downloads/HeadphoneProject/config/karabiner-earpods-unbind-volume.json)

That rule targets only your EarPods device (`vendor_id` `1452`, `product_id` `4363`, consumer device) and replaces `volume_increment` / `volume_decrement` with `vk_none`.

## Suggested First Test

1. Connect the EarPods.
2. Start HID mode.
3. Press `+`, center, and `-` once each and confirm a macOS notification appears.
4. Double-click and triple-click each button and confirm the matching `*_double` / `*_triple` gesture appears.
5. Hold each button for 2 to 3 seconds and confirm the matching `*_hold` gesture appears.
6. Stop with `Control-C`.

If HID mode is silent, rerun the same sequence in `system` mode.
