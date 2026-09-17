# Contributing to Better GDrive

Thanks for wanting to help. Here's everything you need to get started.

## Development setup

```bash
git clone https://github.com/juanchorossi/better-gdrive.git
cd better-gdrive
brew install xcodegen rclone
xcodegen generate
```

Download the rclone binary from [rclone.org/downloads](https://rclone.org/downloads/), place it at `BetterGDrive/Resources/rclone`, and `chmod +x` it.

Open `BetterGDrive.xcodeproj` in Xcode and hit Cmd+R.

## Making changes

- Edit Swift source files directly — no code generation step needed for logic changes.
- If you add or remove files, edit `project.yml` and run `xcodegen generate` to regenerate the `.xcodeproj`.
- The app uses `rclone rc` (remote control daemon) for all sync operations. See `BetterGDrive/Core/RcloneRC.swift`.

## Submitting a PR

1. Fork the repo and create a branch from `main`.
2. Keep the PR focused — one feature or fix per PR.
3. Describe what you changed and why in the PR description.
4. If it's a UI change, include a screenshot.

## Code style

- Swift, SwiftUI, no third-party dependencies beyond rclone.
- Match the style of the surrounding code.
- Don't add comments that just restate what the code does.

## License

By contributing, you agree that your contributions will be licensed under the Apache License 2.0, the same license as the project.
