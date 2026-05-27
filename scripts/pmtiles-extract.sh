#!/usr/bin/env bash
# Térkép kivágás a Protomaps planet build-ből egy bounding box-szal.
# A pmtiles formátum tud range request-tel működni, így a CLI csak a kívánt
# területet húzza le — a teljes planet (~80 GB) nem kell.
#
# A go-pmtiles binárist Docker-en keresztül futtatjuk, nem kell host-ra telepíteni.

set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/lib.sh"

ensure_data_dir
MAP_DIR="$DATA_DIR/maps"

MAP_LINE=$(yaml_get_map)
ENABLED=$(echo "$MAP_LINE" | cut -d'|' -f1)
BBOX=$(echo "$MAP_LINE" | cut -d'|' -f2)
OUTPUT=$(echo "$MAP_LINE" | cut -d'|' -f3)
SOURCE_TMPL=$(echo "$MAP_LINE" | cut -d'|' -f4)
REFRESH_DAYS=$(echo "$MAP_LINE" | cut -d'|' -f5)

if [[ "$ENABLED" != "true" ]]; then
    log_info "Térkép kikapcsolva a content.yaml-ben, kihagyom."
    exit 0
fi

OUTPUT_PATH="$MAP_DIR/$OUTPUT"

# Frissítendő-e?
need_refresh=1
if [[ -f "$OUTPUT_PATH" ]]; then
    age_days=$(( ($(date +%s) - $(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || stat -f%m "$OUTPUT_PATH")) / 86400 ))
    if [[ "$age_days" -lt "$REFRESH_DAYS" ]]; then
        log_ok "Térkép friss ($age_days nap < $REFRESH_DAYS), kihagyom."
        need_refresh=0
    else
        log_info "Térkép $age_days napos, frissítem."
    fi
fi

if [[ "$need_refresh" -eq 0 ]]; then
    exit 0
fi

# A legfrissebb Protomaps build dátuma — kicsit "okosan" próbálkozunk:
# az aktuális dátumtól visszafelé az első működő linkkel.
log_info "Legfrissebb Protomaps build keresése…"
build_date=""
for offset in 1 2 3 4 5 7 10 14; do
    candidate=$(date -d "$offset days ago" +%Y%m%d 2>/dev/null || date -v-${offset}d +%Y%m%d)
    url="${SOURCE_TMPL/\{date\}/$candidate}"
    if curl -fsI --user-agent "$USER_AGENT" "$url" > /dev/null 2>&1; then
        build_date="$candidate"
        log_ok "Talált build: $candidate"
        break
    fi
done

if [[ -z "$build_date" ]]; then
    log_err "Nem találtam friss Protomaps build-et az elmúlt 2 hétben."
    log_err "Próbáld kézzel: curl -I https://build.protomaps.com/YYYYMMDD.pmtiles"
    exit 1
fi

SOURCE_URL="${SOURCE_TMPL/\{date\}/$build_date}"
log_info "Forrás: $SOURCE_URL"
log_info "BBox:   $BBOX"
log_info "Cél:    $OUTPUT_PATH"
log_info "Ez csak a megadott területet tölti le, nem a teljes planet-et (range requests)."

# pmtiles CLI Docker-konténerben
# Az official image: protomaps/go-pmtiles
docker run --rm \
    -v "$MAP_DIR:/out" \
    --user "${PUID}:${PGID}" \
    protomaps/go-pmtiles:latest \
    extract "$SOURCE_URL" "/out/$OUTPUT" \
        --bbox="$BBOX"

log_ok "Térkép kész: $OUTPUT_PATH"
ls -lh "$OUTPUT_PATH"
