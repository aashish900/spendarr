# spendarr

Offline-first expense tracker (Android client). See `../CLAUDE.md` for
Android-client rules and `../docs/CONTEXT.md` for architecture/env facts.

## Dev loop

```bash
cd android/app
flutter pub get
flutter analyze
flutter test
flutter run -d <device-id>
```

## Building a release APK

### One-time setup — generate the signing keystore

Android refuses to install an unsigned APK. The keystore + its passwords are
**gitignored** and must live on your dev machine only (and, for CI, as GitHub
Actions secrets — see below). **Generate once, keep forever** — if you lose
them you can't ship an update of this app over an existing install (you'd
have to uninstall + reinstall, which clears the app's secure storage).

1. **Generate the keystore.** From the repo root:

   ```bash
   keytool -genkey -v \
     -keystore android/app/android/keystore.jks \
     -alias spendarr \
     -keyalg RSA -keysize 2048 \
     -validity 10000
   ```

   `keytool` ships with the JDK (Android Studio installs it). It will prompt for:

   - **Keystore password** (twice). Pick a strong one and save it in your password manager.
   - **Distinguished-name fields** (CN, OU, O, L, ST, C). For a personal sideload these can be anything — `spendarr / personal / aashish / na / na / IN` is fine. They show up in the cert if anyone inspects the APK; not user-facing.
   - **Key password** (twice). Pressing Enter reuses the keystore password — recommended.

   Output: `android/app/android/keystore.jks` (gitignored).

2. **Create `key.properties`.** Copy the example and fill in the passwords from step 1:

   ```bash
   cp android/app/android/key.properties.example android/app/android/key.properties
   # then edit android/app/android/key.properties:
   #   storePassword=<the one you typed at the keytool prompt>
   #   keyPassword=<same as storePassword if you pressed Enter>
   #   keyAlias=spendarr
   #   storeFile=keystore.jks
   ```

   Also gitignored. `storeFile` is resolved relative to `android/app/android/`.

3. **Verify the keystore.** Quick sanity check:

   ```bash
   keytool -list -v -keystore android/app/android/keystore.jks -alias spendarr
   ```

   Should print the cert fingerprint without errors.

### Build + install locally

```bash
cd android/app
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk

adb install build/app/outputs/flutter-apk/app-release.apk
```

If `key.properties` is missing, Gradle silently falls back to the debug key.
That APK installs but is **not shippable** — it'll get refused as an
"update" of any real release-signed install. The build log shows
`signingConfig signingConfigs.debug` in that case; check it before
declaring a build "release".

### CI: publish via GitHub Actions

`.github/workflows/android-publish.yml` builds and attaches a release APK to
a GitHub Release whenever a `v*` tag is pushed:

```bash
git tag v0.1.0
git push --tags
```

The workflow needs the keystore from step 1 as four repo secrets (Settings →
Secrets and variables → Actions):

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -i android/app/android/keystore.jks \| tr -d '\n' \| pbcopy`, paste the clipboard contents |
| `ANDROID_KEY_ALIAS` | `spendarr` |
| `ANDROID_KEY_PASSWORD` | the key password from step 1 |
| `ANDROID_STORE_PASSWORD` | the keystore password from step 1 |

### What's gitignored

- `android/app/android/keystore.jks`
- `android/app/android/key.properties`
- Any `**/*.jks` anywhere in the tree (belt + suspenders).

## Further reading

- `../CLAUDE.md` — Android-client Claude rules.
- `../docs/CONTEXT.md` — env, target device, architecture, what the app does NOT do.
- `../docs/DECISIONLOG.md` — ADRs.
- `../docs/CHANGELOG.md` — per-task history.
- `../docs/ROADMAP.md` — milestone sequence.
- `/CLAUDE.md` — project-wide rules (Tailscale-only, never commit secrets, etc.).
