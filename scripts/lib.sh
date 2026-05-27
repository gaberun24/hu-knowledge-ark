#!/usr/bin/env bash
# Közös függvények és környezet a hu-knowledge-ark scriptekhez.
# Ne futtasd közvetlenül — `source scripts/lib.sh` a többi script tetején.

set -euo pipefail

# A repo gyökérkönyvtára (innen ahonnan a lib.sh fut)
ARK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# .env beolvasása ha létezik
if [[ -f "$ARK_ROOT/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$ARK_ROOT/.env"
    set +a
fi

# Alapértelmezett értékek (ha az .env nincs vagy nem definiál mindent)
DATA_DIR="${DATA_DIR:-$ARK_ROOT/data}"
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
KIWIX_PORT="${KIWIX_PORT:-8888}"
LANDING_PORT="${LANDING_PORT:-5050}"
TZ="${TZ:-Europe/Budapest}"

CONFIG_FILE="$ARK_ROOT/config/content.yaml"

# ANSI színek a barátságosabb outputhoz
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_CYAN=$'\033[36m'
else
    C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_CYAN=""
fi

log_info()  { echo "${C_BLUE}[i]${C_RESET} $*"; }
log_ok()    { echo "${C_GREEN}[✓]${C_RESET} $*"; }
log_warn()  { echo "${C_YELLOW}[!]${C_RESET} $*" >&2; }
log_err()   { echo "${C_RED}[x]${C_RESET} $*" >&2; }
log_step()  { echo; echo "${C_BOLD}${C_CYAN}==> $*${C_RESET}"; }

# YAML értékek olvasása. Egyszerű grep/sed-alapú — kis YAML-okhoz elég.
# Nincs Python függőség, hogy a host gépeken is fusson Python venv nélkül.
#
# Használat: yaml_get_global key
yaml_get_global() {
    local key="$1"
    grep -E "^${key}:" "$CONFIG_FILE" | head -1 | sed -E "s/^${key}:[[:space:]]*\"?([^\"]*)\"?[[:space:]]*$/\1/"
}

# Beolvassa a zim_sources tömböt content.yaml-ből és kiírja
# `id|pattern|base_url|title|category|enabled` formátumban (egy sor / tétel).
yaml_list_zim_sources() {
    python3 - "$CONFIG_FILE" <<'PYEOF'
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as f:
    data = yaml.safe_load(f)
for s in data.get("zim_sources", []):
    print("|".join([
        str(s.get("id","")),
        str(s.get("pattern","")),
        str(s.get("base_url","")),
        str(s.get("title","")),
        str(s.get("category","")),
        str(s.get("enabled", False)).lower(),
    ]))
PYEOF
}

# Map szekció lekérése: enabled|bbox|output_name|source_url|refresh_days
yaml_get_map() {
    python3 - "$CONFIG_FILE" <<'PYEOF'
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as f:
    data = yaml.safe_load(f)
m = data.get("map", {}) or {}
print("|".join([
    str(m.get("enabled", False)).lower(),
    str(m.get("bbox","")),
    str(m.get("output_name","")),
    str(m.get("source_url","")),
    str(m.get("refresh_days", 30)),
]))
PYEOF
}

# Settings szekció: keep_versions|user_agent|download_rate_limit_kb
yaml_get_settings() {
    python3 - "$CONFIG_FILE" <<'PYEOF'
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as f:
    data = yaml.safe_load(f)
s = data.get("settings", {}) or {}
print("|".join([
    str(s.get("keep_versions", 1)),
    str(s.get("user_agent","hu-knowledge-ark/1.0")),
    str(s.get("download_rate_limit_kb", 0)),
]))
PYEOF
}

# Egy URL-en lévő index.html-ből kiszedi az adott pattern-nek megfelelő
# legfrissebb fájlt. A Kiwix download listák ABC-rendezettek, az ISO-dátumos
# fájlnevek miatt a legnagyobb (sort -r) a legfrissebb.
#
# Használat: find_latest_remote_file <base_url> <glob_pattern>
find_latest_remote_file() {
    local base_url="$1"
    local pattern="$2"
    # glob → regex: a "*"-t ".*"-ra cseréljük, a "."-ot escape-eljük
    local regex
    regex=$(echo "$pattern" | sed -E 's/\./\\./g; s/\*/[^"]*/g')
    curl -fsSL --user-agent "$USER_AGENT" "$base_url" \
        | grep -oE "${regex}" \
        | sort -ru \
        | head -1
}

# DATA_DIR struktúra létrehozása ha még nincs
ensure_data_dir() {
    mkdir -p "$DATA_DIR/zim" "$DATA_DIR/maps"
}

# User agent a beállításokból
load_user_agent() {
    local s
    s=$(yaml_get_settings)
    USER_AGENT="$(echo "$s" | cut -d'|' -f2)"
    export USER_AGENT
}
load_user_agent
