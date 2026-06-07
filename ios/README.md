# iOS app

The SwiftUI client lives in **`StarterApp/`**. It is a [Tuist](https://tuist.io/) project: the Xcode project is generated from `Project.swift`, not committed.

## Quick start

From the **repository root**, the usual flow is:

```sh
make dev
```

That script refreshes local Supabase/backend URLs in `Config-Debug.xcconfig`, runs `tuist generate`, and launches the Simulator. See the root **[README.md](../README.md)** and **[local-setup.md](../local-setup.md)** for prerequisites, signing, and physical-device tunnels.

## Xcode only

```sh
cd StarterApp
tuist install    # when Tuist/Package.swift dependencies change
tuist generate   # creates StarterApp.xcodeproj
open StarterApp.xcodeproj
```

From the repo root you can also run **`make ios-gen`** to regenerate the project without a full dev stack.
