#!/usr/bin/env bash
# Kill-Nano: prevent Chrome from downloading its on-device foundational AI model.
set -Eeuo pipefail

POLICY_DIR=/etc/opt/chrome/policies/managed
POLICY_FILE="$POLICY_DIR/disable-genai-local-model.json"
DNS_FILE="$POLICY_DIR/kill-nano-doh.json"
POLICY_JSON=$'{\n  "GenAILocalFoundationalModelSettings": 1\n}'
DNS_JSON=$'{\n  "DnsOverHttpsMode": "automatic"\n}'
CHROME_CONFIG="${HOME:?}/.config/google-chrome"
CHROME_CACHE="${HOME:?}/.cache/google-chrome"

ACTION=install
DRY_RUN=0
SKIP_CLEANUP=0
DNS_AUTOMATIC=0

usage() {
  cat <<'HELP'
Kill-Nano for Google Chrome on Debian/Ubuntu.

Usage: ./kill-google-nano.sh [--status | --restore] [--dry-run]
                             [--skip-cleanup] [--doh-automatic]

Default: install the Chrome managed policy blocking local AI model downloads;
         remove known downloaded model folders if Chrome is not running.
--status         Report policy state without changing anything.
--restore        Remove only Kill-Nano's own, unmodified policy files.
--dry-run        Describe actions without writing or deleting anything.
--skip-cleanup   Keep existing downloaded model folders.
--doh-automatic  ALSO manage DNS-over-HTTPS in automatic mode (opt-in).
                 This may lock the Secure DNS UI; see README before use.
HELP
}

for arg in "$@"; do
  case "$arg" in
    --status) ACTION=status ;;
    --restore) ACTION=restore ;;
    --dry-run) DRY_RUN=1 ;;
    --skip-cleanup) SKIP_CLEANUP=1 ;;
    --doh-automatic) DNS_AUTOMATIC=1 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$arg" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "$ACTION" != install && ( "$SKIP_CLEANUP" -eq 1 || "$DNS_AUTOMATIC" -eq 1 ) ]]; then
  echo 'Cleanup/DoH options are only valid when installing.' >&2
  exit 2
fi

if [[ "$HOME" != /* || "$HOME" == / ]]; then
  echo 'HOME must be an absolute path to a non-root user directory.' >&2
  exit 2
fi

policy_matches() {
  local path=$1 expected=$2
  [[ -f "$path" && ! -L "$path" ]] || return 1
  cmp -s <(printf '%s\n' "$expected") "$path"
}

show_status() {
  if policy_matches "$POLICY_FILE" "$POLICY_JSON"; then
    echo 'Model-download policy: installed (Kill-Nano content).'
  elif [[ -e "$POLICY_FILE" || -L "$POLICY_FILE" ]]; then
    echo 'Model-download policy: different content; not managed by this script.'
  else
    echo 'Model-download policy: absent.'
  fi
  if policy_matches "$DNS_FILE" "$DNS_JSON"; then
    echo 'Optional DNS-over-HTTPS policy: automatic (managed).'
  elif [[ -e "$DNS_FILE" || -L "$DNS_FILE" ]]; then
    echo 'Optional DNS-over-HTTPS policy: different content; not managed.'
  else
    echo 'Optional DNS-over-HTTPS policy: absent.'
  fi
  echo 'Note: other Chrome policies can also affect these settings. Check chrome://policy.'
}

# Never overwrite arbitrary policy files, including symlinks.
check_safe_file() {
  local path=$1 expected=$2
  if [[ -e "$path" || -L "$path" ]] && ! policy_matches "$path" "$expected"; then
    printf 'Refusing to replace modified or foreign policy: %s\n' "$path" >&2
    exit 1
  fi
}

install_policy() {
  local path=$1 contents=$2
  if policy_matches "$path" "$contents"; then
    printf 'Already installed: %s\n' "$path"
    return
  fi
  if (( DRY_RUN )); then
    printf '[dry-run] Would install %s\n' "$path"
    return
  fi
  sudo install -d -m 0755 "$POLICY_DIR"
  local tmp
  tmp=$(sudo mktemp "$POLICY_DIR/.kill-nano.XXXXXXXX")
  if ! printf '%s\n' "$contents" | sudo tee "$tmp" >/dev/null; then
    sudo rm -f -- "$tmp"
    echo 'Could not write Chrome policy.' >&2
    exit 1
  fi
  sudo chmod 0644 "$tmp"
  sudo mv -- "$tmp" "$path"
  printf 'Installed: %s\n' "$path"
}

chrome_running() {
  local uid
  uid=$(id -u)
  pgrep -u "$uid" -x chrome >/dev/null 2>&1 ||
    pgrep -u "$uid" -x google-chrome >/dev/null 2>&1
}

remove_model_dirs() {
  local target
  local -a targets=(
    "$CHROME_CONFIG/OptGuideOnDeviceModel"
    "$CHROME_CACHE/OptGuideOnDeviceModel"
  )

  if chrome_running; then
    echo 'Chrome is running. Not deleting live model data; close Chrome and rerun to clean up.'
    return
  fi
  for target in "${targets[@]}"; do
    if [[ -L "$target" ]]; then
      printf 'Refusing to remove symlink: %s\n' "$target" >&2
      continue
    fi
    if [[ -d "$target" ]]; then
      if (( DRY_RUN )); then
        printf '[dry-run] Would remove %s\n' "$target"
      else
        rm -rf -- "$target"
        printf 'Removed: %s\n' "$target"
      fi
    fi
  done
}

if [[ "$ACTION" == status ]]; then
  show_status
  exit 0
fi

if (( EUID == 0 )); then
  echo 'Run as the affected normal user, not as root; sudo is used only for policies.' >&2
  exit 1
fi

if [[ "$ACTION" == restore ]]; then
  # Validate both targets before deleting either one.
  check_safe_file "$POLICY_FILE" "$POLICY_JSON"
  check_safe_file "$DNS_FILE" "$DNS_JSON"
  for item in "$POLICY_FILE" "$DNS_FILE"; do
    expected=$POLICY_JSON
    [[ "$item" == "$DNS_FILE" ]] && expected=$DNS_JSON
    check_safe_file "$item" "$expected"
    if policy_matches "$item" "$expected"; then
      if (( DRY_RUN )); then
        printf '[dry-run] Would remove %s\n' "$item"
      else
        sudo rm -- "$item"
        printf 'Restored (removed): %s\n' "$item"
      fi
    fi
  done
  echo 'Chrome may have other managed policies. Restart it and inspect chrome://policy.'
  exit 0
fi

check_safe_file "$POLICY_FILE" "$POLICY_JSON"
if (( DNS_AUTOMATIC )); then
  check_safe_file "$DNS_FILE" "$DNS_JSON"
fi
install_policy "$POLICY_FILE" "$POLICY_JSON"
if (( DNS_AUTOMATIC )); then
  install_policy "$DNS_FILE" "$DNS_JSON"
else
  echo 'DNS-over-HTTPS is unchanged. Managed Chrome may disable Secure DNS by default.'
fi

if (( SKIP_CLEANUP )); then
  echo 'Model-file cleanup skipped by request.'
else
  remove_model_dirs
fi

if [[ -d "$CHROME_CONFIG" || -d "$CHROME_CACHE" ]]; then
  echo 'Checking for remaining weights.bin files (including other Chrome model types):'
  for dir in "$CHROME_CONFIG" "$CHROME_CACHE"; do
    if [[ -d "$dir" ]]; then
      find "$dir" -type f -name weights.bin -print 2>/dev/null || true
    fi
  done
fi
if (( DRY_RUN )); then
  echo '[dry-run] No changes were made.'
else
  echo 'Done. Restart Chrome and verify GenAILocalFoundationalModelSettings = 1 at chrome://policy.'
fi
