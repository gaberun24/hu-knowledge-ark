#!/usr/bin/env bash
# Felépíti a Kiwix library.xml-t a $DATA_DIR/zim alatti ZIM fájlokból.
# A library.xml az amit a kiwix-serve a --library kapcsolóval beolvas indításkor.
#
# Mivel a kiwix-tools nincs feltétlenül a host-on telepítve, a Kiwix Docker
# image-ét hívjuk meg egyszeri konténerként: `kiwix-manage add` minden ZIM-re.

set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/lib.sh"

ensure_data_dir
ZIM_DIR="$DATA_DIR/zim"
LIB_FILE="$DATA_DIR/library.xml"

shopt -s nullglob
zim_files=("$ZIM_DIR"/*.zim)
shopt -u nullglob

if [[ ${#zim_files[@]} -eq 0 ]]; then
    log_warn "Nincs egyetlen ZIM fájl sem itt: $ZIM_DIR"
    log_warn "Futtass előbb: make download"
    # Üres library is jó (a kiwix-serve panaszkodik de fut)
    echo '<?xml version="1.0" encoding="UTF-8"?><library version="20110515"/>' > "$LIB_FILE"
    exit 0
fi

log_info "Library felépítése ${#zim_files[@]} ZIM-ből → $LIB_FILE"

# Új library létrehozása: egy konténer ami a kiwix-tools image-ét használja
# (ugyanaz mint a kiwix-serve), és minden ZIM-re fut egy `kiwix-manage add`.
# A library.xml a DATA_DIR-ben jön létre.
docker run --rm \
    -v "$DATA_DIR:/data" \
    --user "${PUID}:${PGID}" \
    --entrypoint /bin/sh \
    ghcr.io/kiwix/kiwix-tools:latest \
    -c '
        set -e
        cd /data
        rm -f library.xml
        for f in /data/zim/*.zim; do
            echo "  + $(basename "$f")"
            kiwix-manage /data/library.xml add "$f"
        done
        echo "library.xml elkészült"
    '

log_ok "Library kész: $LIB_FILE"
