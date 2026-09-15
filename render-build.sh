#!/usr/bin/env bash
set -euo pipefail

ROOT="$PWD"
TOOLS="$ROOT/.android-build"
SDK="$TOOLS/android-sdk"
JDK="$TOOLS/jdk17"
GRADLE="$TOOLS/gradle-9.6.0"
mkdir -p "$TOOLS" "$SDK/cmdline-tools" "$ROOT/out"

printf '\n== Restore PureHTMLBrowser v2 project ==\n'
if [ -n "${PUREHTML_PROJECT_B64:-}" ]; then
  printf '%s' "$PUREHTML_PROJECT_B64" | base64 -d > "$TOOLS/PureHTMLBrowser.zip"
else
  cat .build/project.b64.part* | base64 -d > "$TOOLS/PureHTMLBrowser.zip"
fi
unzip -t "$TOOLS/PureHTMLBrowser.zip"
rm -rf "$ROOT/PureHTMLBrowser"
unzip -q "$TOOLS/PureHTMLBrowser.zip" -d "$ROOT"

printf '\n== Restore release signing key ==\n'
: "${PUREHTML_KEYSTORE_B64:?missing PUREHTML_KEYSTORE_B64}"
: "${PUREHTML_KEYSTORE_PASSWORD:?missing PUREHTML_KEYSTORE_PASSWORD}"
: "${PUREHTML_KEY_ALIAS:?missing PUREHTML_KEY_ALIAS}"
: "${PUREHTML_KEY_PASSWORD:?missing PUREHTML_KEY_PASSWORD}"
printf '%s' "$PUREHTML_KEYSTORE_B64" | base64 -d > "$TOOLS/purehtml-release.jks"
chmod 600 "$TOOLS/purehtml-release.jks"
export PUREHTML_KEYSTORE_PATH="$TOOLS/purehtml-release.jks"

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

printf '\n== Build signed release APK ==\n'
cd "$ROOT/PureHTMLBrowser"
gradle --no-daemon --stacktrace :app:assembleRelease

APK="$ROOT/PureHTMLBrowser/app/build/outputs/apk/release/app-release.apk"
test -s "$APK"
cp "$APK" "$ROOT/out/PureHTMLBrowser-v2.0.0-release.apk"
"$SDK/build-tools/36.0.0/apksigner" verify --verbose --print-certs "$ROOT/out/PureHTMLBrowser-v2.0.0-release.apk"
sha256sum "$ROOT/out/PureHTMLBrowser-v2.0.0-release.apk" > "$ROOT/out/SHA256.txt"
cat "$ROOT/out/SHA256.txt"
ls -lh "$ROOT/out/PureHTMLBrowser-v2.0.0-release.apk"

printf '\n== Minimize deploy payload ==\n'
cd "$ROOT"
rm -rf "$TOOLS" "$ROOT/PureHTMLBrowser"
find "$ROOT/out" -maxdepth 1 -type f -printf '%f %s bytes\n'
