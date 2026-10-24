#!/usr/bin/env bash
# Rebrand the RustDesk tree as CashDesk and bake in the Cash Consulting server.
#
# Idempotent: every text edit first requires its search pattern exactly once in
# the target file. If the pattern is gone, the edit must already be present,
# otherwise the script fails so an upstream change can never ship a client
# that silently still points at RustDesk's public servers.
#
# Inputs (environment): RENDEZVOUS_SERVER, RS_PUB_KEY, CC_APP_NAME.
# Never give this script the private key; only the .pub value is used.
set -euo pipefail

ROOT=${CASHDESK_ROOT:-$(git rev-parse --show-toplevel)}
cd "$ROOT"

: "${RENDEZVOUS_SERVER:?RENDEZVOUS_SERVER is empty}"
: "${RS_PUB_KEY:?RS_PUB_KEY is empty}"
: "${CC_APP_NAME:?CC_APP_NAME is empty}"
if [[ ! $RS_PUB_KEY =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
  echo "RS_PUB_KEY does not look like a base64 ed25519 public key (44 chars ending in '=')" >&2
  exit 1
fi
if [[ ! $CC_APP_NAME =~ ^[A-Za-z][A-Za-z0-9]*$ ]]; then
  echo "CC_APP_NAME must be a single alphanumeric word (it becomes the exe name)" >&2
  exit 1
fi

ORG="com.cashconsults"
ANDROID_APP_ID="com.cashconsults.cashdesk"
COMPANY="Cash Consulting"
SOURCE_URL="https://github.com/gignsky/cashdesk"
SUPPORT_URL="https://cashconsults.com/support/"
MAINTAINER="Cash Consulting <maxwell@cashconsults.com>"
ICONS="$ROOT/brand/icons"

applied=0
skipped=0
declare -a PROOFS=()

# replace_once FILE SEARCH REPLACEMENT
# Literal, single-line SEARCH; REPLACEMENT may span lines.
replace_once() {
  local file=$1 search=$2 replacement=$3 n marker
  [[ -f $file ]] || { echo "FAIL: $file does not exist" >&2; exit 1; }
  n=$(grep -cF -- "$search" "$file" || true)
  marker=${replacement%%$'\n'*}
  # The marker is checked first because an insertion keeps its search line.
  if grep -qF -- "$marker" "$file"; then
    echo "present  $file :: $marker"
    skipped=$((skipped + 1))
  elif [[ $n -eq 1 ]]; then
    S="$search" R="$replacement" perl -0pi -e 's/\Q$ENV{S}\E/$ENV{R}/' "$file"
    echo "patched  $file :: $search"
    applied=$((applied + 1))
  else
    echo "FAIL: expected exactly one match in $file for: $search (found $n)" >&2
    echo "      upstream changed; update brand/apply.sh before building" >&2
    exit 1
  fi
  PROOFS+=("$file"$'\t'"$marker")
}

# ---------------------------------------------------------------- server + key
CFG=libs/hbb_common/src/config.rs
replace_once "$CFG" \
  'pub const RENDEZVOUS_SERVERS: &[&str] = &["rs-ny.rustdesk.com"];' \
  "pub const RENDEZVOUS_SERVERS: &[&str] = &[\"$RENDEZVOUS_SERVER\"];"
replace_once "$CFG" \
  'pub const RS_PUB_KEY: &str = "OeVuKk5nlHiXp+APNn0Y3pC1Iwpwn44JGqrQCsWqmBw=";' \
  "pub const RS_PUB_KEY: &str = \"$RS_PUB_KEY\";"
replace_once "$CFG" \
  'pub static ref APP_NAME: RwLock<String> = RwLock::new("RustDesk".to_owned());' \
  "pub static ref APP_NAME: RwLock<String> = RwLock::new(\"$CC_APP_NAME\".to_owned());"
replace_once "$CFG" \
  'pub static ref ORG: RwLock<String> = RwLock::new("com.carriez".to_owned());' \
  "pub static ref ORG: RwLock<String> = RwLock::new(\"$ORG\".to_owned());"

# ------------------------------------------------------------ no upstream updates
replace_once src/common.rs \
  'pub fn check_software_update() {' \
  "#[allow(unreachable_code)] // CASHCONSULTS: never offer upstream RustDesk builds
pub fn check_software_update() {
    return;"
replace_once src/updater.rs \
  'pub fn start_auto_update() {' \
  "#[allow(unreachable_code)] // CASHCONSULTS: never offer upstream RustDesk builds
pub fn start_auto_update() {
    return;"

# ------------------------------------------------------- Windows file metadata
BASED="Based on RustDesk (AGPL-3.0)."
for toml in Cargo.toml libs/portable/Cargo.toml; do
  replace_once "$toml" 'ProductName = "RustDesk"' "ProductName = \"$CC_APP_NAME\""
  replace_once "$toml" 'FileDescription = "RustDesk Remote Desktop"' "FileDescription = \"$CC_APP_NAME Remote Support\""
  replace_once "$toml" 'OriginalFilename = "rustdesk.exe"' "OriginalFilename = \"$CC_APP_NAME.exe\""
done
replace_once Cargo.toml 'All rights reserved."' "All rights reserved. $BASED\""

RC=flutter/windows/runner/Runner.rc
replace_once "$RC" 'VALUE "CompanyName", "Purslane Tech Pte. Ltd." "\0"' "VALUE \"CompanyName\", \"$COMPANY\" \"\\0\""
replace_once "$RC" 'VALUE "FileDescription", "RustDesk Remote Desktop" "\0"' "VALUE \"FileDescription\", \"$CC_APP_NAME Remote Support\" \"\\0\""
replace_once "$RC" 'VALUE "InternalName", "rustdesk" "\0"' "VALUE \"InternalName\", \"$CC_APP_NAME\" \"\\0\""
replace_once "$RC" 'All rights reserved." "\0"' "All rights reserved. $BASED\" \"\\0\""
replace_once "$RC" 'VALUE "OriginalFilename", "rustdesk.exe" "\0"' "VALUE \"OriginalFilename\", \"$CC_APP_NAME.exe\" \"\\0\""
replace_once "$RC" 'VALUE "ProductName", "RustDesk" "\0"' "VALUE \"ProductName\", \"$CC_APP_NAME\" \"\\0\""

# ------------------------------------------------------------- Flutter UI text
replace_once flutter/lib/desktop/widgets/tabbar_widget.dart '"RustDesk",' "\"$CC_APP_NAME\","
SETTINGS=flutter/lib/desktop/pages/desktop_setting_page.dart
replace_once "$SETTINGS" "translate('About RustDesk')" "'About $CC_APP_NAME'"
replace_once "$SETTINGS" "launchUrlString('https://rustdesk.com');" "launchUrlString('$SOURCE_URL');"
replace_once "$SETTINGS" "translate('Website')," "'Source code (GitHub)',"
replace_once "$SETTINGS" "launchUrlString('https://rustdesk.com/privacy.html');" "launchUrlString('$SUPPORT_URL');"
replace_once "$SETTINGS" \
  "'Copyright © \${DateTime.now().toString().substring(0, 4)} Purslane Tech Pte. Ltd.\\n\$license'," \
  "'$CC_APP_NAME is based on RustDesk (AGPL-3.0). Source: $SOURCE_URL\\nCopyright © \${DateTime.now().toString().substring(0, 4)} Purslane Tech Pte. Ltd.\\n\$license',"
INSTALL=flutter/lib/desktop/pages/install_page.dart
replace_once "$INSTALL" "'https://rustdesk.com/privacy.html')," "'$SUPPORT_URL'),"
replace_once "$INSTALL" "message: 'https://rustdesk.com/privacy.html'," "message: '$SUPPORT_URL',"

# ------------------------------------------------------------------- Android
replace_once flutter/android/app/build.gradle 'applicationId "com.carriez.flutter_hbb"' "applicationId \"$ANDROID_APP_ID\""
MANIFEST=flutter/android/app/src/main/AndroidManifest.xml
replace_once "$MANIFEST" 'android:label="RustDesk"' "android:label=\"$CC_APP_NAME\""
replace_once "$MANIFEST" 'android:label="RustDesk Input"' "android:label=\"$CC_APP_NAME Input\""
STRINGS=flutter/android/app/src/main/res/values/strings.xml
replace_once "$STRINGS" '<string name="app_name">RustDesk</string>' "<string name=\"app_name\">$CC_APP_NAME</string>"
replace_once "$STRINGS" 'when RustDesk screen sharing is established' "when $CC_APP_NAME screen sharing is established"
replace_once "$STRINGS" 'Keeps the RustDesk remote desktop host' "Keeps the $CC_APP_NAME remote desktop host"
replace_once flutter/android/app/src/main/res/values/ic_launcher_background.xml \
  '<color name="ic_launcher_background">#ffffff</color>' \
  '<color name="ic_launcher_background">#06341e</color>'
KT=flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb
replace_once "$KT/MainService.kt" 'const val DEFAULT_NOTIFY_TITLE = "RustDesk"' "const val DEFAULT_NOTIFY_TITLE = \"$CC_APP_NAME\""
replace_once "$KT/MainService.kt" 'val channelName = "RustDesk Service"' "val channelName = \"$CC_APP_NAME Service\""
replace_once "$KT/MainService.kt" 'description = "RustDesk Service Channel"' "description = \"$CC_APP_NAME Service Channel\""
replace_once "$KT/BootReceiver.kt" '"RustDesk is Open"' "\"$CC_APP_NAME is Open\""

# --------------------------------------------------------------------- Linux
# Package, binary, service and /usr/share paths stay "rustdesk": build.py and
# res/DEBIAN hard-code them in dozens of places. Only user-visible text changes.
replace_once res/rustdesk.desktop 'Name=RustDesk' "Name=$CC_APP_NAME"
replace_once res/rustdesk.desktop 'Comment=Remote Desktop' "Comment=Remote support by $COMPANY"
replace_once res/rustdesk-link.desktop 'Name=RustDesk' "Name=$CC_APP_NAME"
replace_once res/rustdesk.service 'Description=RustDesk' "Description=$CC_APP_NAME"
replace_once build.py 'Maintainer: rustdesk <info@rustdesk.com>' "Maintainer: $MAINTAINER"
replace_once build.py 'Homepage: https://rustdesk.com' "Homepage: $SOURCE_URL"
replace_once build.py 'Description: A remote control software.' "Description: $CC_APP_NAME remote support client by $COMPANY (based on RustDesk)"
LINUXAPP=flutter/linux/my_application.cc
replace_once "$LINUXAPP" 'gtk_header_bar_set_title(header_bar, "rustdesk");' "gtk_header_bar_set_title(header_bar, \"$CC_APP_NAME\");"
replace_once "$LINUXAPP" 'gtk_window_set_title(window, "rustdesk");' "gtk_window_set_title(window, \"$CC_APP_NAME\");"

# --------------------------------------------------------------------- icons
[[ -d $ICONS ]] || { echo "FAIL: $ICONS missing; run brand/gen-icons.py --out brand/icons" >&2; exit 1; }
icons_copied=0
while IFS= read -r -d '' src; do
  rel=${src#"$ICONS"/}
  [[ -f $rel ]] || { echo "FAIL: upstream no longer has $rel; update brand/gen-icons.py" >&2; exit 1; }
  if cmp -s "$src" "$rel"; then
    echo "present  $rel"
  else
    cp "$src" "$rel"
    echo "copied   $rel"
    icons_copied=$((icons_copied + 1))
  fi
done < <(find "$ICONS" -type f -print0 | sort -z)

# -------------------------------------------------------------------- proof
echo
echo "== brand/apply.sh summary: $applied edits applied, $skipped already present, $icons_copied icons copied =="
fail=0
for entry in "${PROOFS[@]}"; do
  file=${entry%%$'\t'*}
  marker=${entry#*$'\t'}
  if ! grep -qF -- "$marker" "$file"; then
    echo "MISSING  $file :: $marker" >&2
    fail=1
  fi
done
[[ $fail -eq 0 ]] || exit 1
echo "server : $(grep -F 'pub const RENDEZVOUS_SERVERS' "$CFG")"
echo "key    : $(grep -F 'pub const RS_PUB_KEY' "$CFG")"
echo "app    : $(grep -F 'pub static ref APP_NAME' "$CFG")"
echo "org    : $(grep -F 'pub static ref ORG' "$CFG")"
echo "exe    : $(grep -F 'OriginalFilename' Cargo.toml)"
echo "android: $(grep -F 'applicationId' flutter/android/app/build.gradle)"
if grep -rqF 'rs-ny.rustdesk.com' "$CFG"; then
  echo "FAIL: upstream rendezvous server still present in $CFG" >&2
  exit 1
fi
echo "ok"
