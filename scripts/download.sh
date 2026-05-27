#!/usr/bin/env bash
# Első letöltés (vagy hiányzó tételek pótlása).
# Beolvassa a content.yaml-t és minden enabled ZIM-re lefuttatja a frissítőt.
#
# Használat: scripts/download.sh
#
# Idempotens: ha minden megvan és friss, semmit nem csinál.

set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/lib.sh"

log_step "hu-knowledge-ark — első letöltés / kiegészítés"
log_info "Adatkönyvtár: $DATA_DIR"

ensure_data_dir
"$ARK_ROOT/scripts/update.sh" "$@"

log_step "Térkép kivágás (ha engedélyezett)"
"$ARK_ROOT/scripts/pmtiles-extract.sh" "$@"

log_step "Kiwix library újraépítése"
"$ARK_ROOT/scripts/build-library.sh"

log_ok "Kész. Indítsd el a stack-et: make up"
