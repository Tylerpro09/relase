#!/usr/bin/env bash
set -euo pipefail

ROOT="$PWD"
TOOLS="$ROOT/.android-build"
SDK="$TOOLS/android-sdk"
JDK="$TOOLS/jdk17"
GRADLE="$TOOLS/gradle-9.6.0"
PROJECT_ZIP="$TOOLS/PureBrowser-2.1-source.zip"
EXPECTED_PROJECT_SHA="40536ad8ffa29431ea7df364bc9a6926d184d7c7d395449a7988acb24de5bf00"
mkdir -p "$TOOLS" "$SDK/cmdline-tools" "$ROOT/out"
rm -f "$ROOT/out"/*

printf '\n== Restore Pure Browser 2.1 project ==\n'
cat .build/v21.b64.part00 .build/v21.b64.part01 .build/v21.b64.part02 .build/v21.b64.part03 .build/v21.b64.part04 .build/v21.b64.part05 .build/v21.b64.part06 .build/v21.b64.part07 | tr -d '[:space:]' | base64 -d > "$PROJECT_ZIP"
ACTUAL_PROJECT_SHA="$(sha256sum "$PROJECT_ZIP" | awk '{print $1}')"
echo "Project SHA256: $ACTUAL_PROJECT_SHA"
[ "$ACTUAL_PROJECT_SHA" = "$EXPECTED_PROJECT_SHA" ] || { echo "Project payload checksum mismatch"; exit 2; }
unzip -t "$PROJECT_ZIP"
rm -rf "$ROOT/PureHTMLBrowser"
unzip -q "$PROJECT_ZIP" -d "$ROOT"

MAIN_ACTIVITY="$ROOT/PureHTMLBrowser/app/src/main/java/com/mandarin/purehtmlbrowser/MainActivity.java"
grep -q 'ApplicationInfo.FLAG_DEBUGGABLE' "$MAIN_ACTIVITY"
grep -q "versionName '2.1.0'" "$ROOT/PureHTMLBrowser/app/build.gradle"

printf '\n== Restore private release signing key ==\n'
: "${PUREHTML_KEYSTORE_B64:?missing PUREHTML_KEYSTORE_B64}"
: "${PUREHTML_KEYSTORE_PASSWORD:?missing PUREHTML_KEYSTORE_PASSWORD}"
: "${PUREHTML_KEY_PASSWORD:?missing PUREHTML_KEY_PASSWORD}"
: "${PUREHTML_KEY_ALIAS:?missing PUREHTML_KEY_ALIAS}"
printf '%s' "$PUREHTML_KEYSTORE_B64" | base64 -d > "$TOOLS/purebrowser-release.jks"
chmod 600 "$TOOLS/purebrowser-release.jks"
export PURE_RELEASE_KEYSTORE="$TOOLS/purebrowser-release.jks"
export PURE_RELEASE_STORE_PASSWORD="$PUREHTML_KEYSTORE_PASSWORD"
export PURE_RELEASE_KEY_PASSWORD="$PUREHTML_KEY_PASSWORD"
export PURE_RELEASE_KEY_ALIAS="$PUREHTML_KEY_ALIAS"

if [ ! -x "$JDK/bin/java" ]; then
  rm -rf "$TOOLS/jdk-tmp" "$JDK"
  mkdir -p "$TOOLS/jdk-tmp" "$JDK"
  curl -fL --retry 4 --retry-delay 2 'https://api.adoptium.net/v3/binary/latest/17/ga/linux/x64/jdk/hotspot/normal/eclipse' -o "$TOOLS/jdk17.tar.gz"
  tar -xzf "$TOOLS/jdk17.tar.gz" -C "$TOOLS/jdk-tmp"
  JDK_SRC="$(find "$TOOLS/jdk-tmp" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  cp -a "$JDK_SRC"/. "$JDK"/
fi
export JAVA_HOME="$JDK"
export PATH="$JAVA_HOME/bin:$PATH"

if [ ! -x "$GRADLE/bin/gradle" ]; then
  curl -fL --retry 4 --retry-delay 2 'https://services.gradle.org/distributions/gradle-9.6.0-bin.zip' -o "$TOOLS/gradle.zip"
  unzip -q -o "$TOOLS/gradle.zip" -d "$TOOLS"
fi
export PATH="$GRADLE/bin:$PATH"

if [ ! -x "$SDK/cmdline-tools/latest/bin/sdkmanager" ]; then
  rm -rf "$SDK/cmdline-tools/latest" "$TOOLS/cmdline-unzip"
  mkdir -p "$TOOLS/cmdline-unzip"
  curl -fL --retry 4 --retry-delay 2 'https://dl.google.com/android/repository/commandlinetools-linux-15859902_latest.zip' -o "$TOOLS/cmdline-tools.zip"
  unzip -q "$TOOLS/cmdline-tools.zip" -d "$TOOLS/cmdline-unzip"
  mkdir -p "$SDK/cmdline-tools/latest"
  cp -a "$TOOLS/cmdline-unzip/cmdline-tools"/. "$SDK/cmdline-tools/latest"/
fi
export ANDROID_HOME="$SDK"
export ANDROID_SDK_ROOT="$SDK"
export PATH="$SDK/cmdline-tools/latest/bin:$SDK/platform-tools:$PATH"
yes | sdkmanager --licenses >/dev/null || true
sdkmanager 'platforms;android-36' 'build-tools;36.0.0' 'platform-tools'

printf '\n== Build signed Pure Browser 2.1 release ==\n'
cd "$ROOT/PureHTMLBrowser"
gradle --no-daemon --stacktrace :app:assembleRelease
APK="$ROOT/PureHTMLBrowser/app/build/outputs/apk/release/app-release.apk"
OUT="$ROOT/out/PureBrowser-2.1-release.apk"
test -s "$APK"
cp "$APK" "$OUT"

printf '\n== Verify signature and hash ==\n'
"$SDK/build-tools/36.0.0/apksigner" verify --verbose --print-certs "$OUT"
sha256sum "$OUT" > "$ROOT/out/SHA256.txt"
cat "$ROOT/out/SHA256.txt"
stat -c '%n %s bytes' "$OUT"

printf '\n== APK64 transfer ==\n'
echo 'APK64_BEGIN'
base64 -w0 "$OUT" | fold -w 6000 | awk '{printf "APK64:%03d:%s\n", NR-1, $0}'
echo 'APK64_END'

printf '\n== Minimize deploy payload ==\n'
cd "$ROOT"
rm -rf "$TOOLS" "$ROOT/PureHTMLBrowser" "$HOME/.gradle"
find "$ROOT/out" -maxdepth 1 -type f -printf '%f %s bytes\n'
