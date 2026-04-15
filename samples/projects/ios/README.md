# iOS sample project

A minimal one-form project (Label + Edit + Button) that exercises the
iOS backend end-to-end.

## Run it

1. Open `Project1.hbp` in HarbourBuilder (macOS IDE).
2. Select **Run → Run on iOS...**
3. The IDE will:
   - generate `_generated.prg` from the form using UI_* API calls
   - build a signed `HarbourApp.app` for the simulator
   - install and launch it on the iPhone Simulator

You should see a native iOS screen with:

- a **Label** `"Type your name:"`
- a **UITextField** you can type into
- a **UIButton** `"Greet"` that updates the label to `"Hello, <name> !"`
  when tapped

## How the iOS target works

The same `Form1.prg` runs on macOS/Windows/Linux through `TForm` and on
iOS through `UI_*` primitives. The backend (`ios_core.m`) creates real
UIKit controls — UILabel, UIButton, UITextField — via Objective-C, using
the same HB_FUNC API as the Android backend.

The event loop is inverted on iOS: `UIApplicationMain()` owns the run
loop, and Harbour's `UI_FormRun()` is a no-op. The AppDelegate starts
the Harbour VM in `application:didFinishLaunchingWithOptions:`, which
runs `Main()` to create the controls, then returns control to the
iOS event loop.

See `docs/en/platform-ios.html` for the full architecture.

## Prerequisites

- macOS with **Xcode 15+** installed
- iOS SDK (installed via Xcode > Settings > Platforms)
- Harbour for macOS at `~/harbour/bin/harbour`
- Harbour iOS libraries at `~/harbour-ios-src/lib/darwin/clang-ios-arm64/`

Run **Run → iOS Setup Wizard...** to check and install missing components.
