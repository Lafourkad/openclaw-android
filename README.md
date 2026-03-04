# OpenClaw for Android

Run [OpenClaw](https://openclaw.ai) natively on Android — no root, no Termux, no Ubuntu required.

## What is this?

A standalone Android APK that downloads and runs the OpenClaw AI gateway directly on your phone. Your agents (Telegram, Discord, WhatsApp) run locally on the device.

## Features

- **Standalone** — no external dependencies, single APK
- **GrapheneOS compatible** — works around `noexec` filesDir via native library dir
- **Full runtime** — Node.js 22, Python 3.13, Go 1.26 bundled at bootstrap
- **Integrated terminal** — shell access with `openclaw`, `node`, `npm`, `python3`, `go`
- **Agent workspace** — agents can use `exec` to run code in all three runtimes
- **Auto-migration** — imports config from `/sdcard/openclaw-migrate.json` on first run

## How it works

On first launch, the app downloads and installs:
1. glibc 2.42 (ARM64) — required to run Linux binaries on Android
2. Node.js 22 — the OpenClaw runtime
3. OpenClaw — the AI gateway (688 packages)
4. Python 3.13 — for agent scripting
5. Go 1.26 — for agent tooling

All binaries run via `ld.so` from the native library directory (the only executable location on GrapheneOS). Wrapper scripts in `/data/local/tmp/` give agents real `execve`-able access to all runtimes.

**Download size:** ~300MB (one-time), **APK size:** 27.7MB

## Build

```bash
export JAVA_HOME=~/android-build/jdk-17 ANDROID_HOME=~/android-build/android-sdk
export PATH=$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:~/flutter/bin:$PATH

cd flutter_app
flutter build apk --release --target-platform android-arm64
```

## Credits

- **[Mithun Gowda B](https://github.com/mithun50/openclaw-termux)** — original Flutter app structure
- **[Aidan Park](https://github.com/AidanPark/openclaw-android)** — glibc-on-Android approach
- **[OpenClaw](https://openclaw.ai)** — the AI gateway

## By

[@0xGrug](https://x.com/0xGrug)

## License

MIT
