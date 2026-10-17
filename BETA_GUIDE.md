# Inlay Beta Guide

## What Inlay Is

Inlay is a hidden EarPods-controlled layer for:

- resuming what matters
- capturing named threads for later
- starting and managing timers
- checking what is playing
- using a lightweight voice-and-text Companion for short commands

It is not a general desktop assistant. It is strongest when you keep requests short and direct.

## Current Best Use Cases

- `start a five minute timer`
- `open chrome`
- `search figma docs`
- `open current thread`
- `open work queue`
- `what's playing`
- `pause music`
- `capture this`
- `undo that`

## Current Boundaries

- Companion opens fresh browser searches. It does not reliably switch existing tabs.
- Browser-backed `Now Playing` only reads the frontmost supported browser media tab.
- Speech is good enough for beta, but still less trustworthy than typed input.
- Timer currently has one focused timer plus a visible summary of any additional timers.

## Install

`Inlay.app` is currently unsigned for beta.

To open it:

1. Download `Inlay.app` or a zip containing it.
2. Move it somewhere normal like `Applications` or `Downloads`.
3. Right-click the app and choose `Open`.
4. Click `Open` again in the macOS warning.

If macOS still blocks it:

1. Open `System Settings -> Privacy & Security`
2. Find the blocked app message
3. Click `Open Anyway`

## Hardware / Environment

- macOS
- wired Apple EarPods inline controls

Inlay is designed around:

- `+`
- `-`
- `center tap`
- `center double`
- `center hold`

## First Run

On first launch:

1. Complete the launcher setup overlay by doing `+`, `-`, and a quick center tap once each.
2. Hold center to finish launcher setup.
3. Create a 4-step Cipher unlock code and confirm it.

After that, Inlay goes quiet in the background until you call it.

## Core Gestures

- `center_hold` opens the launcher
- `+` and `-` move through rows
- `center_tap` confirms
- `center_hold` backs out of most pages
- `center_double` is used in some pages for secondary actions or closing Companion

## Companion

Companion is strongest with short commands across a few domains:

- timer
- search
- apps
- work queue
- current thread
- media
- capture
- undo / management

Best current flow:

- hold center to speak
- release to send
- if Companion is unsure, choose a fallback
- if needed, say `teach this as ...`

Examples:

- `teach this as timer`
- `teach this as search`
- `teach this as work queue`
- `teach this as chrome`

Typed input is still the best debugging path when voice feels off.

## Support / Recovery

If Inlay feels hidden:

1. Launch `Inlay.app` again.
2. That should wake the running hidden instance.

If it still feels stuck:

1. Open `Support`
2. Try `Restart Inlay`

Support also includes:

- `Open Speech Settings`
- `Open Microphone Settings`
- `Open Accessibility Settings`
- `Open Companion Help`
- `Reveal Logs`
- `Reveal Support Files`

## What To Test

### Launcher / Surfaces

- launcher opens reliably with `center_hold`
- `Support` works and navigation feels normal
- `Current Thread` names the current app/context well
- `Work Queue` capture/resume/remove/label flows feel clear
- `Timer` handles one timer and multiple timers sensibly
- `Now Playing` works with Spotify, Music, and frontmost browser media

### Companion

- hold-to-speak feels natural
- live transcript updates while you talk
- common phrases map cleanly
- low-confidence cases offer useful fallback choices
- `Teach This` actually improves repeated phrases
- spoken follow-ups feel sensible

### Recovery

- relaunching the app wakes it
- `Support -> Restart Inlay` works
- permission prompts are visible and not hidden behind Inlay

## Feedback To Capture

When reporting an issue, the most useful details are:

- exactly what you said or typed
- what Inlay did instead
- whether it was voice or typed
- what page you were in
- whether Support / Restart fixed it

If possible, also include:

- a screenshot
- the log folder from `Support -> Reveal Logs`
