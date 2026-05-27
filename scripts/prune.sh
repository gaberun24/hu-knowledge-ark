#!/usr/bin/env bash
# Letakarítja:
#   - a `.partial` fájlokat (megszakadt letöltések)
#   - a content.yaml-ben kikapcsolt (`enabled: false`) ZIM-eket
#   - a régi verziókat (settings.keep_versions felett)
#
# Használat: scripts/prune.sh [--dry-run]

set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/lib.sh"

DRY_RUN=0
[[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]] && DRY_RUN=1

ensure_data_dir
ZIM_DIR="$DATA_DIR/zim"

SETTINGS=$(yaml_get_settings)
KEEP_VERSIONS=$(echo "$SETTINGS" | cut -d'|' -f1)

rm_or_say() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_info "[dry-run] törölné: $1"
    else
        rm -f "$1"
        log_ok "Törölve: $1"
    fi
}

log_step ".partial fájlok takarítása"
shopt -s nullglob
for f in "$ZIM_DIR"/*.partial; do
    rm_or_say "$f"
done
shopt -u nullglob

log_step "Kikapcsolt forrásokhoz tartozó ZIM-ek"
# Megnézzük melyik id-k vannak enabled=true-val. A többi id-prefix törölhető.
enabled_ids=()
while IFS='|' read -r id _ _ _ _ enabled; do
    [[ "$enabled" == "true" ]] && enabled_ids+=("$id")
done < <(yaml_list_zim_sources)

shopt -s nullglob
for f in "$ZIM_DIR"/*.zim; do
    # A fájlnév formátuma: <id>__<eredeti>.zim
    base=$(basename "$f")
    file_id="${base%%__*}"
    found=0
    for eid in "${enabled_ids[@]}"; do
        if [[ "$file_id" == "$eid" ]]; then
            found=1
            break
        fi
    done
    if [[ "$found" -eq 0 ]]; then
        log_info "$base — már nem enabled (id=$file_id)"
        rm_or_say "$f"
    fi
done
shopt -u nullglob

log_step "Régi verziók (settings.keep_versions=$KEEP_VERSIONS felett)"
# Minden enabled id-re: ha több verzió van, csak a legfrissebb $KEEP_VERSIONS-t tartsuk meg
for eid in "${enabled_ids[@]}"; do
    shopt -s nullglob
    versions=("$ZIM_DIR"/"${eid}"__*.zim)
    shopt -u nullglob
    if [[ ${#versions[@]} -gt $KEEP_VERSIONS ]]; then
        # Rendezzük időbélyeg szerint csökkenőbe (legfrissebb először)
        IFS=$'\n' sorted=($(printf '%s\n' "${versions[@]}" | sort -r))
        unset IFS
        for f in "${sorted[@]:$KEEP_VERSIONS}"; do
            rm_or_say "$f"
        done
    fi
done

log_ok "Letakarítás kész."
