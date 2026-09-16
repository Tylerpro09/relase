#!/usr/bin/env bash
set -euo pipefail

ROOT="$PWD"
TOOLS="$ROOT/.android-build"
SDK="$TOOLS/android-sdk"
JDK="$TOOLS/jdk17"
GRADLE="$TOOLS/gradle-9.6.0"
PROJECT_ZIP="$TOOLS/PureBrowser-2.0-base.zip"
EXPECTED_PROJECT_SHA="e2509e07378c8ccb5c1688f41209c4e4f80dbc25a06101f367812d9fcedd85a0"
EXPECTED_V22_B64_SHA="bc6c302a200e966a47f19cdae18414b9c46115482f4247820b5c2d6049bb3cf2"
EXPECTED_V23_B64_SHA="c37c1af1bcb897a2a6b791f5c9b4324f148494ad802347da22bb90b349b1393a"
EXPECTED_V24_B64_SHA="9fa15758de3f041ef52437b95dbfafe12b78fbdc5bd0b4e86ce404fbce439d17"
mkdir -p "$TOOLS" "$SDK/cmdline-tools" "$ROOT/out"
rm -f "$ROOT/out"/*

printf '\n== Restore verified Pure Browser 2.0 base ==\n'
cat .build/v2.bin.part* > "$PROJECT_ZIP"
ACTUAL_PROJECT_SHA="$(sha256sum "$PROJECT_ZIP" | awk '{print $1}')"
echo "Base project SHA256: $ACTUAL_PROJECT_SHA"
[ "$ACTUAL_PROJECT_SHA" = "$EXPECTED_PROJECT_SHA" ] || { echo "Base project checksum mismatch"; exit 2; }
unzip -t "$PROJECT_ZIP"
rm -rf "$ROOT/PureHTMLBrowser"
unzip -q "$PROJECT_ZIP" -d "$ROOT"

printf '\n== Apply Pure Browser 2.1 native-permissions patch ==\n'
base64 -d .build/v21.patch.gz.b64 | gzip -dc > "$TOOLS/v21.patch"
patch -p1 --batch --forward < "$TOOLS/v21.patch"
MAIN_ACTIVITY="$ROOT/PureHTMLBrowser/app/src/main/java/com/mandarin/purehtmlbrowser/MainActivity.java"
# The verified 2.0 payload predates the AGP 9 BuildConfig compatibility fix.
sed -i 's/WebView\.setWebContentsDebuggingEnabled(BuildConfig\.DEBUG);/WebView.setWebContentsDebuggingEnabled((getApplicationInfo().flags \& android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0);/' "$MAIN_ACTIVITY"
grep -q 'ApplicationInfo.FLAG_DEBUGGABLE' "$MAIN_ACTIVITY"
grep -q 'PureAndroidBridge' "$MAIN_ACTIVITY"
grep -q 'ACTIVITY_RECOGNITION' "$MAIN_ACTIVITY"
grep -q "versionName '2.1.0'" "$ROOT/PureHTMLBrowser/app/build.gradle"
grep -q "androidx.webkit:webkit:1.17.0" "$ROOT/PureHTMLBrowser/app/build.gradle"

printf '\n== Apply Pure Browser 2.2 site-permissions patch ==\n'
cat .build/v22.part* > "$TOOLS/v22.patch.gz.b64"
ACTUAL_V22_B64_SHA="$(sha256sum "$TOOLS/v22.patch.gz.b64" | awk '{print $1}')"
echo "2.2 patch payload SHA256: $ACTUAL_V22_B64_SHA"
[ "$ACTUAL_V22_B64_SHA" = "$EXPECTED_V22_B64_SHA" ] || { echo "2.2 patch checksum mismatch"; exit 3; }
base64 -d "$TOOLS/v22.patch.gz.b64" | gzip -dc > "$TOOLS/v22.patch"
patch -p3 --batch --forward < "$TOOLS/v22.patch"
grep -q "versionName '2.2.0'" "$ROOT/PureHTMLBrowser/app/build.gradle"
grep -q 'bridgeVersion' "$MAIN_ACTIVITY"
grep -q 'bodySensors' "$MAIN_ACTIVITY"
grep -q 'showNotification' "$MAIN_ACTIVITY"
grep -q 'secure_origin_required' "$MAIN_ACTIVITY"

printf '\n== Apply Pure Browser 2.3 native-vibration patch ==\n'
ACTUAL_V23_B64_SHA="$(sha256sum .build/v23.patch.gz.b64 | awk '{print $1}')"
echo "2.3 patch payload SHA256: $ACTUAL_V23_B64_SHA"
[ "$ACTUAL_V23_B64_SHA" = "$EXPECTED_V23_B64_SHA" ] || { echo "2.3 patch checksum mismatch"; exit 4; }
base64 -d .build/v23.patch.gz.b64 | gzip -dc > "$TOOLS/v23.patch"
cd "$ROOT/PureHTMLBrowser"
patch -p3 --batch --forward < "$TOOLS/v23.patch"
cd "$ROOT"
grep -q "versionName '2.3.0'" "$ROOT/PureHTMLBrowser/app/build.gradle"
grep -q 'performSiteVibration' "$MAIN_ACTIVITY"
grep -q 'VibrationEffect.createOneShot' "$MAIN_ACTIVITY"
grep -q "Object.defineProperty(navigator,'vibrate'" "$MAIN_ACTIVITY"

printf '\n== Apply Pure Browser 2.4 polish patch ==\n'
ACTUAL_V24_B64_SHA="$(sha256sum .build/v24.patch.gz.b64 | awk '{print $1}')"
echo "2.4 patch payload SHA256: $ACTUAL_V24_B64_SHA"
[ "$ACTUAL_V24_B64_SHA" = "$EXPECTED_V24_B64_SHA" ] || { echo "2.4 patch checksum mismatch"; exit 5; }
base64 -d .build/v24.patch.gz.b64 | gzip -dc > "$TOOLS/v24.patch"
patch -p1 --batch --forward < "$TOOLS/v24.patch"
grep -q "versionName '2.4.0'" "$ROOT/PureHTMLBrowser/app/build.gradle"
grep -q 'DOCUMENT_START_SCRIPT' "$MAIN_ACTIVITY"
grep -q 'SITE_WEB_PREFIX' "$MAIN_ACTIVITY"
grep -q 'showSettingsDialog' "$MAIN_ACTIVITY"
grep -q 'haptic:function' "$MAIN_ACTIVITY"

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

printf '\n== JDK 17 ==\n'
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

printf '\n== Gradle 9.6 ==\n'
if [ ! -x "$GRADLE/bin/gradle" ]; then
  curl -fL --retry 4 --retry-delay 2 'https://services.gradle.org/distributions/gradle-9.6.0-bin.zip' -o "$TOOLS/gradle.zip"
  unzip -q -o "$TOOLS/gradle.zip" -d "$TOOLS"
fi
export PATH="$GRADLE/bin:$PATH"

printf '\n== Android SDK 36 ==\n'
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

printf '\n== Build signed Pure Browser 2.4 release ==\n'
cd "$ROOT/PureHTMLBrowser"
gradle --no-daemon --stacktrace :app:assembleRelease
APK="$ROOT/PureHTMLBrowser/app/build/outputs/apk/release/app-release.apk"
OUT="$ROOT/out/PureBrowser-2.4-release.apk"
test -s "$APK"
cp "$APK" "$OUT"

printf '\n== Verify signature and hash ==\n'
"$SDK/build-tools/36.0.0/apksigner" verify --verbose --print-certs "$OUT"
sha256sum "$OUT" > "$ROOT/out/SHA256.txt"
cat "$ROOT/out/SHA256.txt"
stat -c '%n %s bytes' "$OUT"

printf '\n== Minimize deploy payload ==\n'
cd "$ROOT"
rm -rf "$TOOLS" "$ROOT/PureHTMLBrowser" "$HOME/.gradle"
find "$ROOT/out" -maxdepth 1 -type f -printf '%f %s bytes\n'
