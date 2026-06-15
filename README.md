# Spool

A native macOS menu-bar screen recorder in the spirit of Loom: record your screen
with a floating **camera bubble**, microphone narration, and system audio, then upload
the finished recording straight to **[Frame.io](https://frame.io)** for storage and
sharing.

> The git repo is named `loom`, but the app is called **Spool** to avoid confusion
> with the real Loom product.

## Features

- 🎥 Record a full display or a single window (ScreenCaptureKit).
- 🫧 Floating, draggable, always-on-top **camera bubble** — captured in-frame, so it
  appears in the final video with no compositing.
- 🎙️ Microphone narration + 🔊 system audio, muxed into the `.mp4`.
- ☁️ One-click upload to Frame.io (V4 API) with a shareable link when it finishes.
- 🔐 Sign in with Adobe (OAuth 2.0 + PKCE via Adobe IMS); tokens stored in the Keychain.
- 🧭 Menu-bar only — no Dock clutter.

## Requirements

- macOS 14.0 (Sonoma) or later.
- Xcode 15+.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
- A Frame.io account and an Adobe Developer Console project (see below).

## Build & run

```bash
brew install xcodegen      # one time
xcodegen generate          # generates Spool.xcodeproj from project.yml
open Spool.xcodeproj
```

In Xcode: select the **Spool** scheme, set your Apple Developer **Team** under
Signing & Capabilities (automatic signing), then **Run** (⌘R). A camera icon appears
in the menu bar.

> The project file is generated and git-ignored — always run `xcodegen generate`
> after pulling changes to `project.yml`.

### First-run permissions

macOS will prompt for **Screen Recording**, **Camera**, and **Microphone** the first
time you record. Grant them in **System Settings → Privacy & Security**. Screen
Recording in particular requires re-launching the app after granting.

### ⚠️ "Spool would like to record this computer's screen" keeps prompting

If the Screen Recording prompt reappears on every launch **even though Spool is already
toggled on** in System Settings, the cause is almost always an **unstable code
signature**. macOS ties permission grants to the app's code-signing identity, not just
its name. An app signed *ad-hoc* ("Sign to Run Locally", which is what Xcode uses when
**no Development Team is selected**) gets a **new signature on every build**, so macOS
treats each build as a different app and re-prompts — while the stale entry lingers in
the list.

**Fix it once:**

1. In Xcode → target **Spool** → **Signing & Capabilities**, enable **Automatically
   manage signing** and select your **Team** (a free personal Apple ID team works).
   This gives the app a stable *Apple Development* identity that survives rebuilds.
   Avoid "Sign to Run Locally" / "None".
2. Quit Spool, then reset its stale permission entries and re-grant once:
   ```bash
   ./Scripts/reset-permissions.sh     # runs tccutil reset for Spool
   ```
   (or manually: select **Spool** in each Privacy list and click the **–** button.)
3. Rebuild & run, then grant Screen Recording once and relaunch.

Also keep a single copy of `Spool.app` — running it from multiple paths (or from a
quarantined/translocated location) can defeat the permission match too.


## Frame.io / Adobe Developer Console setup

Frame.io's V4 API authenticates through Adobe IMS, so you register an OAuth app once:

1. Go to the [Adobe Developer Console](https://developer.adobe.com/console) and create
   a new **Project**.
2. **Add API → Frame.io API** to the project.
3. Add an **OAuth credential** (e.g. *OAuth Native App*). Adobe generates a
   **Redirect URI** for it — for a Native App credential it looks like:
   ```
   adobe+<hash>://adobeid/<client_id>
   ```
   Spool doesn't require a specific scheme; it uses whatever redirect URI you give it.
4. Copy both the **Client ID** and the **Redirect URI** from the credential.
5. Launch Spool → **Settings** (⌘,) → paste the **Client ID** *and* the **Redirect URI**
   exactly as shown in the console → **Sign in with Adobe**.
6. After signing in, pick an **Account → Workspace → Project** as the upload
   destination. Recordings upload to that project's root folder.

> **The Redirect URI must match exactly.** If it doesn't, the Adobe consent screen
> appears but after "Allow access" the window dead-ends on a blank `…/ims/fromSusi#`
> page and sign-in never completes — because Adobe redirects to its registered URI,
> not the one Spool is listening for.

> **Your Frame.io user must be linked to your Adobe ID**, or every API call returns
> `401 "Your Frame user is not linked to an Adobe ID."` Sign in once at
> [app.frame.io](https://app.frame.io) with the same Adobe account; for a pre-existing
> Frame.io account, link it under **Account Settings → Profile → Authentication**
> (the Frame.io and Adobe emails must match).

You can also bake the Client ID in at build time by adding a `SPOOL_ADOBE_CLIENT_ID`
key to `Sources/App/Info.plist`.

## How it works

```
SpoolApp (MenuBarExtra)
└── AppState ──────────────── orchestrates everything
    ├── RecordingCoordinator
    │   ├── ScreenCaptureEngine   SCStream → screen video + system audio
    │   ├── CameraEngine          AVCaptureSession → webcam (shown in the bubble)
    │   ├── MicrophoneEngine      AVCaptureSession → mic audio
    │   ├── CameraBubbleWindow    circular floating preview (captured in-frame)
    │   └── MovieWriter           AVAssetWriter → H.264 + AAC .mp4
    └── FrameIO
        ├── FrameIOAuth           OAuth 2.0 + PKCE via Adobe IMS, Keychain tokens
        ├── FrameIOClient         accounts / workspaces / projects / folders
        └── FrameIOUploader       local-upload create + chunked presigned-S3 PUT
```

The camera bubble is an ordinary on-screen window, so ScreenCaptureKit records it
in-frame — giving the Loom look without per-frame video compositing.

Recordings are written to `~/Movies/Spool/`. If you're not signed in, they're simply
saved there locally.

## Tests

Pure-logic pieces are unit-tested (run on a Mac):

```bash
xcodegen generate
xcodebuild test -scheme Spool -destination 'platform=macOS'
```

- `PKCETests` — PKCE verifier/challenge (incl. the RFC 7636 vector).
- `ChunkPlanTests` — upload chunk tiling math.

## Limitations / roadmap

- The camera bubble is captured in-frame rather than composited, so its on-screen
  position is baked into the video. A true composited bubble (resizable after the
  fact) is a future enhancement.
- Mic and system audio are written as **separate tracks**; some players show two
  audio tracks. A mixed single track is a possible follow-up.
- No pause/resume, trimming, or annotations yet.
- App Sandbox is disabled for this MVP (see `Sources/App/Spool.entitlements`).

## License

TBD.
