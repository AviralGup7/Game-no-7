# Release notes & build guide — Large Print Hitori

Everything below was verified on this repository, not copied from a template.

---

## Verified build output

| Artifact | Command | Size |
|---|---|---|
| Release APK (arm64) | `flutter build apk --release --target-platform android-arm64` | **21.7 MB** |
| Play bundle | `flutter build appbundle --release` | **47.9 MB** |

`package` `com.aviralgupta.large_print_hitori` · label **Large Print Hitori** ·
`minSdk` 24 · `targetSdk` 36 · `versionCode` 1 / `versionName` 1.0.0 · 2 dex
files · all 12 audio assets bundled.

Quality gates, all passing:

* `flutter analyze` — **no issues**
* `flutter test` — **65 tests pass**
* `bash tool/verify_assets.sh` — **passes** (audio 2.4 MB, within the 6 MB budget)
* `python tool/generate_icons.py` — **byte-reproducible**, zero diff on regeneration

---

## BEFORE YOU CAN SHIP — four blockers

These are real, and every one will stop a release.

### 1. The release build is DEBUG-SIGNED

Verified:

```
$ keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab
Owner: C=US, O=Android, CN=Android Debug
```

`android/app/build.gradle.kts` falls back to debug signing when
`android/key.properties` is missing, so a fresh clone still builds. **Play
rejects a debug-signed AAB.**

```bash
bash tool/make_keystore.sh      # never been run
flutter build appbundle --release
```

Back up the `.jks` and its passwords somewhere you will still have them in
five years. Losing them means you cannot update the app under the same listing
without a Google key-reset request.

### 2. AdMob IDs are Google's TEST IDs

| Where | Value |
|---|---|
| `AndroidManifest.xml` `APPLICATION_ID` | `ca-app-pub-3940256099942544~3347511713` |
| Interstitial (Android) | `ca-app-pub-3940256099942544/1033173712` |
| Rewarded (Android) | `ca-app-pub-3940256099942544/5224354917` |

Shipping these means **zero revenue**. Do not swap in real IDs during
development either — clicking your own live ads is the fastest route to a
policy strike, and one strike can terminate the whole AdMob account.

### 3. The `remove_ads` product does not exist yet

Create a **one-time (non-consumable) managed product** with product ID
`remove_ads` in the Play Console. Never a subscription. Until it exists,
`IapService.available` is false and the button is correctly disabled.

### 4. Never run on a physical device

This is the honest gap. Everything is verified by unit test, widget test and
static analysis on a headless Linux machine. Nothing has been in a human hand.
Specifically unverified for THIS game:

* Whether an 8×8 grid's cells are comfortably tappable. The board is square
  and fills the width, so on a 320 dp screen a cell is roughly 38 dp — below
  the 56 dp button guidance. Drag-to-paint is the mitigation, but only a real
  thumb can confirm it is enough.
* Whether the dimmed number on a shaded cell is genuinely readable in
  sunlight. It measures 4.5:1+ but that is a calculation, not an eye.
* Whether drag-to-paint misfires when a player means to tap.
* Audio balance through a phone speaker.

---

## Reproducing the build

### Toolchain

```bash
# Flutter 3.35.7
curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.35.7-stable.tar.xz" -o fl.tar.xz
tar xf fl.tar.xz -C /path/to/toolchain

# JDK 21 — AGP 8.9 needs 17+
sudo apt-get install -y openjdk-21-jdk-headless

# Android SDK
sdkmanager "platform-tools" "platforms;android-36" "platforms;android-35" \
           "build-tools;35.0.0" "ndk;27.0.12077973"

export ANDROID_HOME=/path/to/android-sdk
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
export PATH=$JAVA_HOME/bin:/path/to/flutter/bin:$PATH
flutter config --android-sdk $ANDROID_HOME --jdk-dir $JAVA_HOME
```

### Build failures that recur on small machines

**1. `Gradle build daemon disappeared unexpectedly`**
The kernel OOM-killed it. Confirm with `dmesg | grep -i "killed process"`.
**Fix — swap is mandatory on anything under ~8 GB:**

```bash
sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
```

This build used ~900 MB of swap on a 2 GB host. Without it, it cannot
complete. `android/gradle.properties` is tuned to match (`-Xmx1100m`,
`workers.max=1`, `parallel=false`, serial GC); Flutter's default `-Xmx8G`
guarantees an OOM kill here.

**2. `Could not read workspace metadata from .../caches/*/transforms/*/metadata.bin`**
A Gradle cache corrupted by the machine being reset mid-write. **Fix:**
`rm -rf $GRADLE_USER_HOME` — forces a ~4 minute re-download.

**3. NDK `did not have a source.properties file`**
A half-extracted NDK from an interrupted download. **Fix:**
`rm -rf $ANDROID_HOME/ndk && sdkmanager "ndk;27.0.12077973"`, then verify with
`ls $ANDROID_HOME/ndk/*/source.properties` BEFORE building.

**4. `android/local.properties` needs a trailing newline.** Appending with
`echo >>` onto a file without one produces
`flutter.sdk=/path/to/fluttersdk.dir=/path/to/sdk`, and the resulting error
points at `settings.gradle.kts`, nowhere near the real cause. Write it with
`printf`.

---

## Build timings (2 cores, 2 GB RAM + 4 GB swap)

| Phase | Time |
|---|---|
| Gradle first-run download | ~4 min |
| Auto-installed SDK 34 + CMake + NDK bits | ~2 min |
| Kotlin/Java compile, R8, dex, package | ~7 min |
| **Total, cold** | **~13 min** |
| Incremental AAB after that | ~5 min |

---

## Store listing rules for this portfolio

* **Never claim a cognitive or medical benefit.** Not "improves memory", not
  "fights decline", not "brain training". Lumosity paid a **$2M FTC
  settlement** for exactly that copy. The approved strapline is
  *"Big print · No timer · Offline"*.
* **Never buy installs or reviews.** One policy strike can terminate the
  developer account, taking every other title with it.
* Closed testing: personal accounts created after 2023-11-13 need **12 testers
  for 14 consecutive days**. Organisation accounts (with a D-U-N-S number) are
  exempt. See
  <https://support.google.com/googleplay/android-developer/answer/14151465>.

---

## Asset licensing

Every third-party asset is **CC0**. Full provenance in
[`ATTRIBUTION.md`](ATTRIBUTION.md), including the duration check that caught
two 10 ms silent files. The board, icons and store graphics are generated from
source in this repo and carry no third-party licence at all.
