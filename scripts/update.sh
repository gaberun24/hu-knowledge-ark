#!/usr/bin/env bash
# A content.yaml minden enabled ZIM-jére:
#   - lekéri a base_url HTML-jét
#   - megtalálja a pattern-nek megfelelő legfrissebb fájlt
#   - összehasonlítja a lokálissal
#   - letölti az újat ha frissebb, hash-szel ellenőrzi
#   - régi verziókat töröl (keep_versions szerint)
#   - újraépíti a library.xml-t és restart-olja a kiwix konténert
#
# Használat:
#   scripts/update.sh           # minden enabled tételt
#   scripts/update.sh --dry-run # csak megmutatja mit csinálna
#   scripts/update.sh wiktionary_hu  # csak ezt az id-t

set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/lib.sh"

DRY_RUN=0
ONLY_ID=""
for arg in "$@"; do
    case "$arg" in
        --dry-run|-n) DRY_RUN=1 ;;
        --help|-h)
            echo "Használat: $0 [--dry-run] [zim_id]"
            exit 0
            ;;
        --*) log_warn "Ismeretlen flag: $arg" ;;
        *) ONLY_ID="$arg" ;;
    esac
done

ensure_data_dir
ZIM_DIR="$DATA_DIR/zim"

# Beállítások betöltése
SETTINGS=$(yaml_get_settings)
KEEP_VERSIONS=$(echo "$SETTINGS" | cut -d'|' -f1)
RATE_LIMIT=$(echo "$SETTINGS" | cut -d'|' -f3)

CURL_OPTS=(--fail --silent --show-error --location --user-agent "$USER_AGENT")
WGET_OPTS=(--quiet --show-progress --user-agent="$USER_AGENT")
if [[ "$RATE_LIMIT" -gt 0 ]]; then
    WGET_OPTS+=("--limit-rate=${RATE_LIMIT}k")
fi

CHANGED=0
SKIPPED=0
DISABLED_FOUND=0

while IFS='|' read -r id pattern base_url title category enabled; do
    [[ -z "$id" ]] && continue
    if [[ -n "$ONLY_ID" && "$id" != "$ONLY_ID" ]]; then
        continue
    fi

    if [[ "$enabled" != "true" ]]; then
        # Ha letöltött fájlja van a disablen, jelezzük (de nem törlünk automatikusan)
        if compgen -G "$ZIM_DIR/${id}__*.zim" > /dev/null; then
            log_warn "$id: kikapcsolt, de lokálisan van letöltött fájl. Töröld kézzel vagy futtass: make prune"
            DISABLED_FOUND=$((DISABLED_FOUND+1))
        fi
        continue
    fi

    log_step "$title  ($id)"

    # Legfrissebb távoli verzió neve
    remote_file=$(find_latest_remote_file "$base_url" "$pattern" || true)
    if [[ -z "$remote_file" ]]; then
        log_err "Nem találtam $pattern-nek megfelelő fájlt itt: $base_url"
        log_err "Lehet hogy megszűnt a Kiwix-en, vagy hálózati hiba."
        continue
    fi
    log_info "Legfrissebb távoli: $remote_file"

    # Lokális fájlnév: <id>__<eredeti név>  (a prefix segít a könnyű azonosításban)
    local_path="$ZIM_DIR/${id}__${remote_file}"

    if [[ -f "$local_path" ]]; then
        # Lokális méret-check: ne legyen 0 byte / félig letöltött
        size=$(stat -c%s "$local_path" 2>/dev/null || stat -f%z "$local_path")
        if [[ "$size" -gt 1000000 ]]; then
            log_ok "Lokálisan már megvan, kihagyom ($((size/1024/1024)) MB)"
            SKIPPED=$((SKIPPED+1))
            continue
        else
            log_warn "Lokális fájl gyanúsan kicsi, újratöltöm"
            rm -f "$local_path"
        fi
    fi

    # Régebbi verziók a könyvtárban
    older=()
    while IFS= read -r f; do older+=("$f"); done < <(ls -t "$ZIM_DIR"/"${id}"__*.zim 2>/dev/null || true)

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_info "[dry-run] letöltené: $remote_file → $local_path"
        if [[ ${#older[@]} -gt $KEEP_VERSIONS ]]; then
            log_info "[dry-run] törölné: ${older[*]:$KEEP_VERSIONS}"
        fi
        continue
    fi

    # Letöltés .partial-ba, hash check, aztán atomic move
    tmp_path="${local_path}.partial"
    log_info "Letöltés: ${base_url}${remote_file}"
    wget "${WGET_OPTS[@]}" -O "$tmp_path" "${base_url}${remote_file}"

    # Hash ellenőrzés ha van .sha256
    sha_url="${base_url}${remote_file}.sha256"
    if curl -fsI --user-agent "$USER_AGENT" "$sha_url" > /dev/null 2>&1; then
        log_info "Hash ellenőrzés…"
        expected=$(curl "${CURL_OPTS[@]}" "$sha_url" | awk '{print $1}')
        actual=$(sha256sum "$tmp_path" | awk '{print $1}')
        if [[ "$expected" != "$actual" ]]; then
            log_err "Hash NEM EGYEZIK. Várt: $expected  Kapott: $actual"
            rm -f "$tmp_path"
            exit 1
        fi
        log_ok "Hash OK."
    else
        log_warn "Nincs .sha256 távoli fájl, hash ellenőrzés kihagyva."
    fi

    mv "$tmp_path" "$local_path"
    log_ok "Új fájl: $(basename "$local_path") ($(($(stat -c%s "$local_path" 2>/dev/null || stat -f%z "$local_path")/1024/1024)) MB)"
    CHANGED=$((CHANGED+1))

    # Régi verziók eltakarítása
    # Az `older` az új letöltés ELŐTTI állapotot tartalmazta, mind régi.
    # Tartsunk meg keep_versions darabot.
    if [[ ${#older[@]} -gt $KEEP_VERSIONS ]]; then
        for f in "${older[@]:$KEEP_VERSIONS}"; do
            log_info "Régi verzió törlése: $(basename "$f")"
            rm -f "$f"
        done
    fi
done < <(yaml_list_zim_sources)

echo
log_step "Összefoglaló"
log_info "Frissítve: $CHANGED tétel"
log_info "Változatlan: $SKIPPED tétel"
[[ $DISABLED_FOUND -gt 0 ]] && log_warn "Kikapcsolt, de lokálisan meglévő tétel: $DISABLED_FOUND"

if [[ "$DRY_RUN" -eq 0 && "$CHANGED" -gt 0 ]]; then
    log_step "Library újraépítése"
    "$ARK_ROOT/scripts/build-library.sh"

    # Ha Docker compose elérhető és fut, restart-oljuk a kiwix-et
    if command -v docker > /dev/null && docker compose -f "$ARK_ROOT/docker-compose.yml" ps kiwix 2>/dev/null | grep -q "Up\|running"; then
        log_step "Kiwix konténer újraindítása az új library betöltéséhez"
        docker compose -f "$ARK_ROOT/docker-compose.yml" restart kiwix
        log_ok "Kiwix újraindult."
    fi
fi
