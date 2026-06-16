# Spool — Feature Ideas & Roadmap

A running backlog of Loom-style features we could add to Spool. Not committed work —
just a place to collect and prioritize ideas. Check items off or move them to "Done"
as they land.

## Status legend
- [ ] idea / not started
- [~] in progress
- [x] done

---

## Done
- [x] Screen + window capture (ScreenCaptureKit)
- [x] Camera bubble (floating, captured in-frame)
- [x] Microphone + system audio, mixed to a single track
- [x] Camera & microphone device selection (persisted)
- [x] Frame.io upload (V4, chunked) with OAuth (Adobe IMS + PKCE)
- [x] Saved upload destination (account / workspace / project)
- [x] Public share link after upload + "Copy to clipboard"
- [x] Countdown (3-2-1) before recording starts
- [x] Menu-bar timer showing elapsed recording time
- [x] Global hotkey (⌥⌘R) to start/stop from anywhere

---

## Capture & framing
- [ ] **Region / area selection** — drag to record part of the screen (currently full
  display or a whole window). Biggest capture gap.
- [ ] **Camera bubble polish** — resize, circle/square toggle, mirror, position presets,
  show/hide during recording.
- [x] **Countdown** — 3-2-1 before recording starts.
- [ ] **Cursor effects** — click highlight / spotlight, optional keystroke display.

## During recording
- [x] **Global hotkey** to start/stop without opening the menu (⌥⌘R).
- [x] **Menu-bar timer** — elapsed time in the status item.
- [ ] **Pause / resume.**
- [ ] **Audio level meters** — confirm mic/system levels before recording.

## After recording
- [ ] **Trim** start/end before upload.
- [ ] **Recording history** — list of past recordings with re-copy link, re-upload,
  reveal-in-Finder.
- [ ] **System notification** with the share link when upload completes.
- [ ] **Choose a Frame.io subfolder** (not just the project root).
- [ ] **Prompt for a title** before upload (instead of the timestamp name).

## Output options
- [ ] Resolution / FPS / quality settings.
- [ ] **GIF export.**
- [ ] **Auto-delete local file** after a successful upload (optional).

## Polish / infra
- [ ] Verify the public-share API fields against a live response; handle free-plan
  fallback gracefully.
- [ ] Silence the `MoviePostProcessor` concurrency warnings.
- [ ] App icon + basic branding.

---

## Suggested next batches
1. **Feels like a real recorder:** global hotkey + menu-bar timer + countdown.
2. **Biggest capture gap:** region/area selection.
3. **Sharing polish:** verify share link end-to-end + system notification + recording
   history.
