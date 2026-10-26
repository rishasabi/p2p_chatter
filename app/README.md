# Chatter

Chatter is an offline mesh messenger for Android. Phones talk to each other
directly over Wi-Fi and Bluetooth and relay messages for one another, so a
message gets through with no internet, no phone signal and no server: in a
shelter, at a field hospital, during an outage.

## Features

- Direct chats, and channels that are open or locked with a passphrase
- Works over Wi-Fi (a shared network or a phone's hotspot) and Bluetooth LE,
  and switches between them as phones come and go
- Messages hop through other phones to reach someone out of range, and wait
  up to 24 hours for them to come back
- Delivery and read receipts
- Signed messages, verified contacts and warnings about impersonators
- Connect by scanning a QR code, or pick a Chatter phone from the Nearby list
- A live mesh map of who you can reach, and how
- Markdown, link previews, drafts, alert sounds, and colour themes you can
  share as `.chattertheme` files

## How it works

```
                 one phone
 ┌────────────────────────────────────┐
 │  Flutter UI (lib/)                 │
 │      │ HTTP on 127.0.0.1:8080      │
 │      ▼                             │
 │  Go node (libchatter.so) ──────────┼── Wi-Fi: libp2p over TCP ──► other phones
 │      ▲ frames (/bt/outbox, inbox)  │
 │      ▼                             │
 │  Bluetooth LE (Kotlin) ────────────┼── BLE L2CAP ───────────────► other phones
 └────────────────────────────────────┘
```

- **The app** is Flutter. It draws the UI, keeps chats on the phone and
  owns the Bluetooth radio.
- **The node** does the networking. It's written in Go
  ([`service/`](https://github.com/Swassyman/chatter), a git submodule),
  compiled to `libchatter.so` and loaded into the app through `dart:ffi`.
  The app starts it and then talks to it over an HTTP API that only the
  phone itself can reach.
- **Wi-Fi.** Phones on the same network or hotspot find each other with
  mDNS, a QR code, or through neighbours that pass on who else they can
  reach.
- **Bluetooth.** Go can't drive the radio, so the app's Kotlin code
  advertises, scans and opens L2CAP links, and moves frames between them
  and the node.
- **The mesh.** Every message is signed by its sender and passed on hop by
  hop. Messages for someone out of range are carried until they turn up.
  [The node's README](https://github.com/Swassyman/chatter#readme) has the
  details.
- **Storage.** Chats live in SQLite. Settings, contacts and drafts are JSON
  files, and the node's identity key is `identity.key`, all in the app's
  private storage.

## Layout

| Path | What's there |
| --- | --- |
| `lib/screens/` | Chats (direct and channels), Nearby, Settings, the chat view, QR codes, help |
| `lib/services/` | Starting the node, its HTTP client, Bluetooth, storage, link previews, sounds |
| `lib/application_api.dart` | Ties them together: peers, polling the node, carrying Bluetooth frames |
| `lib/widgets/`, `lib/theme/` | The mesh map, message text and avatars; colours and fonts |
| `android/app/src/main/kotlin/` | Bluetooth LE advertising, scanning and L2CAP sockets |
| `android/app/src/main/jniLibs/` | Prebuilt `libchatter.so` for local builds |
| `test/` | Widget and UI tests |
| [`../service/`](https://github.com/Swassyman/chatter) | The Go node (a submodule) |
| [`../.github/workflows/release.yml`](../.github/workflows/release.yml) | Builds the APKs and publishes releases |

## Build and run

You need Flutter 3.47 (stable), the Android SDK with NDK 27.0.12077973, and
a phone or emulator. Go 1.26.5 or newer is only needed to rebuild the node.

```sh
git clone --recurse-submodules https://github.com/rishasabi/p2p_chatter
cd p2p_chatter/app
flutter run
flutter test
```

The repo includes a prebuilt `libchatter.so` for `arm64-v8a` (phones) and
`x86_64` (emulators). A local `armeabi-v7a` build needs that ABI's library
built first. After changing the Go code, rebuild the libraries (see
[Build for Android](https://github.com/Swassyman/chatter#build-for-android))
and commit them together with the new `service` pointer.

## Releases

[`release.yml`](../.github/workflows/release.yml) builds the APKs on every
pull request and every push to `main`. It compiles `libchatter.so` for each
ABI from the pinned `service` commit, then runs:

```sh
flutter build apk --release --target-platform android-arm,android-arm64,android-x64 \
  --split-per-abi --obfuscate --split-debug-info=build/symbols
```

The version comes from `version:` in `pubspec.yaml`: `1.0.0+1` is version
1.0.0, build 1. When `main` has a version with no release yet, the workflow
tags it `v1.0.0` and publishes:

| File | For |
| --- | --- |
| `chatter-1.0.0-arm64-v8a.apk` | Most phones |
| `chatter-1.0.0-armeabi-v7a.apk` | Older 32-bit phones |
| `chatter-1.0.0-x86_64.apk` | Emulators |
| `chatter-1.0.0-debug-symbols.zip` | Reading crash stack traces with `flutter symbolize` |

To release, raise both numbers (`1.0.0+1` → `1.0.1+2`) and merge to `main`.

Each APK is about 22 MB. Native libraries are stored compressed, which
halves the APK, and Android unpacks them when the app is installed. R8
shrinks the Java and Kotlin code, and `--obfuscate` with
`--split-debug-info` keeps Dart symbols out of the APK.

### Signing

Every release has to be signed with the same key, or phones can't update
from one release to the next. Set the key up once:

```sh
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then add these repository secrets under Settings > Secrets and variables >
Actions:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | The output of `base64 -w0 upload-keystore.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | The keystore password |
| `ANDROID_KEY_ALIAS` | `upload` |
| `ANDROID_KEY_PASSWORD` | The key password, which is the keystore password unless you set another |

Keep `upload-keystore.jks` and its password safe and out of the repo. If
the key is lost, everyone has to uninstall Chatter, losing their chats, to
install the next release. Without the secrets, the workflow still builds,
but it signs with a throwaway debug key and prints a warning.

To sign a local release build with the same key, create
`android/key.properties`, which git ignores. A relative `storeFile` path is
relative to `android/app`.

```properties
storeFile=/path/to/upload-keystore.jks
storePassword=...
keyAlias=upload
keyPassword=...
```
