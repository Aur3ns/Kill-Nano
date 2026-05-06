#!/usr/bin/env bash
set -Eeuo pipefail

# script to block Chrome's local AI model. Tested on Ubuntu & Debian
# Removes OptGuideOnDeviceModel / weights.bin and applies a Chrome policy.

POLICY_DIR="/etc/opt/chrome/policies/managed"
POLICY_FILE="$POLICY_DIR/disable-genai-local-model.json"

CHROME_CONFIG="$HOME/.config/google-chrome"
CHROME_CACHE="$HOME/.cache/google-chrome"

echo "[1/6] Checking user..."

if [ "$(id -u)" -eq 0 ]; then
  echo "Error: run this script as your normal user, not with sudo."
  echo "The script will only use sudo to write the system policy."
  exit 1
fi

echo "[2/6] Closing Chrome..."

pkill -TERM -x chrome 2>/dev/null || true
pkill -TERM -x google-chrome 2>/dev/null || true
sleep 2
pkill -KILL -x chrome 2>/dev/null || true
pkill -KILL -x google-chrome 2>/dev/null || true

echo "[3/6] Creating Chrome policy..."

sudo mkdir -p "$POLICY_DIR"

cat <<JSON | sudo tee "$POLICY_FILE" >/dev/null
{
  "GenAILocalFoundationalModelSettings": 1
}
JSON

sudo chmod 644 "$POLICY_FILE"

echo "[4/6] Removing already downloaded models..."

TARGETS=(
  "$CHROME_CONFIG/OptGuideOnDeviceModel"
  "$CHROME_CONFIG/optimization_guide_model_store"
  "$CHROME_CACHE/OptGuideOnDeviceModel"
  "$CHROME_CACHE/optimization_guide_model_store"
)

for target in "${TARGETS[@]}"; do
  if [ -e "$target" ]; then
    echo "Removing: $target"
    rm -rf "$target"
  fi
done

echo "[5/6] Searching for remaining weights.bin files..."

FOUND="$(find "$CHROME_CONFIG" "$CHROME_CACHE" -type f -name 'weights.bin' 2>/dev/null || true)"

if [ -n "$FOUND" ]; then
  echo "Warning: some weights.bin files still exist:"
  echo "$FOUND"
else
  echo "No weights.bin file found in the user Chrome directories."
fi

echo "[6/6] Done."

echo
echo "Now restart Chrome and check:"
echo "  chrome://policy/"
echo
echo "You should see:"
echo "  GenAILocalFoundationalModelSettings = 1"
echo
echo "You can also verify with:"
echo "  find ~/.config/google-chrome ~/.cache/google-chrome -type f -name 'weights.bin' 2>/dev/null"
