#!/usr/bin/env bash
set -euo pipefail

ROOT="$PWD"
TOOLS="$ROOT/.android-build"
SDK="$TOOLS/android-sdk"
JDK="$TOOLS/jdk17"
GRADLE="$TOOLS/gradle-9.6.0"
PROJECT_ZIP="$TOOLS/PureBrowser-2.0-source.zip"
EXPECTED_PROJECT_SHA="e2509e07378c8ccb5c1688f41209c4e4f80dbc25a06101f367812d9fcedd85a0"
mkdir -p "$TOOLS" "$SDK/cmdline-tools" "$ROOT/out"
rm -f "$ROOT/out"/*

printf '\n== Restore Pure Browser 2.0 project ==\n'
cat .build/v2.bin.part* > "$PROJECT_ZIP"
ACTUAL_PROJECT_SHA="$(sha256sum "$PROJECT_ZIP" | awk '{print $1}')"
echo "Project SHA256: $ACTUAL_PROJECT_SHA"
[ "$ACTUAL_PROJECT_SHA" = "$EXPECTED_PROJECT_SHA" ] || { echo "Project payload checksum mismatch"; exit 2; }
unzip -t "$PROJECT_ZIP"
rm -rf "$ROOT/PureHTMLBrowser"
unzip -q "$PROJECT_ZIP" -d "$ROOT"

printf '\n== Restore private release signing key ==\n'
: "${PURE_RELEASE_KEY_B64:?missing PURE_RELEASE_KEY_B64}"
: "${PURE_RELEASE_STORE_PASSWORD:?missing PURE_RELEASE_STORE_PASSWORD}"
: "${PURE_RELEASE_KEY_PASSWORD:?missing PURE_RELEASE_KEY_PASSWORD}"
: "${PURE_RELEASE_KEY_ALIAS:?missing PURE_RELEASE_KEY_ALIAS}"
printf '%s' "$PURE_RELEASE_KEY_B64" | base64 -d > "$TOOLS/purebrowser-release.jks"
chmod 600 "$TOOLS/purebrowser-release.jks"
export PURE_RELEASE_KEYSTORE="$TOOLS/purebrowser-release.jks"

printf '\n== Download JDK 17 ==\n'
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
java -version

printf '\n== Download Gradle 9.6 ==\n'
if [ ! -x "$GRADLE/bin/gradle" ]; then
  curl -fL --retry 4 --retry-delay 2 'https://services.gradle.org/distributions/gradle-9.6.0-bin.zip' -o "$TOOLS/gradle.zip"
  unzip -q -o "$TOOLS/gradle.zip" -d "$TOOLS"
fi
export PATH="$GRADLE/bin:$PATH"
gradle --version

printf '\n== Download Android command-line tools ==\n'
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

printf '\n== Install Android SDK 36 ==\n'
yes | sdkmanager --licenses >/dev/null || true
sdkmanager 'platforms;android-36' 'build-tools;36.0.0' 'platform-tools'

printf '\n== Build signed, minified release APK ==\n'
cd "$ROOT/PureHTMLBrowser"
gradle --no-daemon --stacktrace :app:assembleRelease

APK="$ROOT/PureHTMLBrowser/app/build/outputs/apk/release/app-release.apk"
OUT="$ROOT/out/PureBrowser-2.0-release.apk"
test -s "$APK"
cp "$APK" "$OUT"

printf '\n== Verify APK signature ==\n'
"$SDK/build-tools/36.0.0/apksigner" verify --verbose --print-certs "$OUT"
sha256sum "$OUT" > "$ROOT/out/SHA256.txt"
cat "$ROOT/out/SHA256.txt"
ls -lh "$OUT"

printf '\n== Minimize deploy payload ==\n'
cd "$ROOT"
rm -rf "$TOOLS" "$ROOT/PureHTMLBrowser" "$HOME/.gradle"
find "$ROOT/out" -maxdepth 1 -type f -printf '%f %s bytes\n'
