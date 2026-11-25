#!/usr/bin/env bash
# Copy the addon (only the files WoW needs) into an AddOns folder for testing.
#   tools/install-dev.sh                 # a fresh scratch folder (default)
#   tools/install-dev.sh /some/AddOns    # a folder you name
# The live Forever AddOns folder is refused unless COMMS_ALLOW_LIVE=1 is set:
# BRIEF says never install there without Tim's OK.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
addons="${1:-$(mktemp -d -t comms-addons-XXXXXX)}"
case "$addons" in
  *_forever_/Interface/AddOns*|*_retail_/Interface/AddOns*|*_classic*/Interface/AddOns*)
    if [ "${COMMS_ALLOW_LIVE:-}" != "1" ]; then
      echo "Refusing to install into a live WoW AddOns folder: $addons" >&2
      echo "(set COMMS_ALLOW_LIVE=1 only with Tim's OK)" >&2
      exit 1
    fi
    ;;
esac
mkdir -p "$addons"
dest="$addons/Comms"
mkdir -p "$dest"
rsync -a --delete \
  --include='*.toc' --include='Bindings.xml' --include='Core/***' --include='Modules/***' --include='UI/***' \
  --include='Media/***' --include='LICENSE' --exclude='*' \
  "$repo/" "$dest/"
echo "Installed to: $dest"
echo "In game: /reload, then /comms"
