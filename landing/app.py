"""
hu-knowledge-ark — landing oldal.

Egy lapos Flask app, ami:
  - kategorizált kártyákat mutat a content.yaml alapján
  - egy közös keresőből továbbít a Kiwix Xapian keresőjébe
  - a /map útvonalon megjeleníti a pmtiles térképet
  - a /healthz egészségellenőrzőt ad
"""
from __future__ import annotations

import glob
import os
import time
from dataclasses import dataclass
from pathlib import Path

import yaml
from flask import Flask, render_template, request, redirect, jsonify, send_from_directory, abort

DATA_DIR = Path(os.environ.get("DATA_DIR", "/data"))
CONFIG_FILE = Path(os.environ.get("CONFIG_FILE", "/app/config/content.yaml"))
KIWIX_PUBLIC_PORT = os.environ.get("KIWIX_PUBLIC_PORT", "8888")

app = Flask(__name__)


@dataclass
class ZimItem:
    """Egy elérhető ZIM kötet a Kiwix library-ben."""
    id: str
    title: str
    description: str
    category: str
    icon: str
    file_name: str
    size_bytes: int
    enabled: bool

    @property
    def size_human(self) -> str:
        return human_size(self.size_bytes)

    @property
    def kiwix_url(self) -> str:
        # A Kiwix a fájlnévből származó "book name"-et használ. A library.xml
        # generálásakor a kiwix-manage automatikusan beállítja, de a fájlnév
        # alapja konvencionálisan a fájl basename-je kiterjesztés nélkül.
        stem = Path(self.file_name).stem
        # A `<host>:<port>/viewer#<book>/<main_url>` formátum a stabil Kiwix UI.
        # A relatív útvonalat használjuk, így bármilyen reverse proxy mögött is megy.
        return f"/kiwix/viewer#{stem}/"


CATEGORY_LABELS = {
    "altalanos":  "Általános tudás",
    "nyelv":      "Nyelv és szótár",
    "oktatas":    "Oktatás, kézikönyvek",
    "irodalom":   "Irodalom, klasszikus szövegek",
    "terkep":     "Térkép",
    "hirek":      "Hírek",
    "egyeb":      "Egyéb",
}


def human_size(n: int) -> str:
    """Pl. 1572864 -> '1.5 MB'."""
    units = ["B", "kB", "MB", "GB", "TB"]
    f = float(n)
    for u in units:
        if f < 1024 or u == units[-1]:
            return f"{f:.1f} {u}".replace(".0 ", " ")
        f /= 1024
    return f"{n} B"


def load_config() -> dict:
    if not CONFIG_FILE.exists():
        return {}
    with CONFIG_FILE.open(encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


def discover_zim_items() -> list[ZimItem]:
    """A config + a /data/zim alatti fájlok összeházasítása."""
    cfg = load_config()
    sources = {s["id"]: s for s in cfg.get("zim_sources", [])}
    zim_dir = DATA_DIR / "zim"

    items: list[ZimItem] = []
    if not zim_dir.exists():
        return items

    # Az id-prefixből visszafejtjük melyik forrásra utal a fájl
    for path in sorted(zim_dir.glob("*.zim")):
        name = path.name
        if "__" in name:
            file_id = name.split("__", 1)[0]
        else:
            file_id = path.stem

        src = sources.get(file_id, {})
        items.append(ZimItem(
            id=file_id,
            title=src.get("title", file_id),
            description=src.get("description", ""),
            category=src.get("category", "egyeb"),
            icon=src.get("icon", "book"),
            file_name=name,
            size_bytes=path.stat().st_size,
            enabled=bool(src.get("enabled", True)),
        ))
    return items


def discover_map() -> dict | None:
    cfg = load_config()
    m = cfg.get("map") or {}
    if not m.get("enabled"):
        return None
    map_path = DATA_DIR / "maps" / m.get("output_name", "")
    if not map_path.exists():
        return None
    return {
        "name": map_path.name,
        "size_human": human_size(map_path.stat().st_size),
        "bbox": m.get("bbox", ""),
        "url": "/static-data/maps/" + map_path.name,
    }


# ---------------------------------------------------------------------------
# Útvonalak
# ---------------------------------------------------------------------------

@app.route("/")
def index():
    items = discover_zim_items()
    # Kategóriába csoportosítjuk
    by_cat: dict[str, list[ZimItem]] = {}
    for it in items:
        by_cat.setdefault(it.category, []).append(it)

    categories = []
    for key, label in CATEGORY_LABELS.items():
        if key in by_cat:
            categories.append({"key": key, "label": label, "items": by_cat[key]})

    # A nem definiált kategóriák a végére
    for key, lst in by_cat.items():
        if key not in CATEGORY_LABELS:
            categories.append({"key": key, "label": key.title(), "items": lst})

    map_info = discover_map()
    return render_template("index.html",
                           categories=categories,
                           map_info=map_info,
                           total_items=len(items))


@app.route("/search")
def search():
    """Áttöltés a Kiwix közös keresőjére."""
    q = request.args.get("q", "").strip()
    if not q:
        return redirect("/")
    # A relatív /kiwix/search a reverse-proxy útvonal — de hagyatkozhatunk
    # a public porton lévő közvetlen Kiwix-re is, hogy CSP-friendly legyen.
    return redirect(f"/kiwix/search?pattern={q}&books.filter.lang=hun")


@app.route("/map")
def map_page():
    map_info = discover_map()
    if not map_info:
        abort(404, description="A térkép nincs letöltve. Futtasd: make download")
    return render_template("map.html", map_info=map_info)


@app.route("/healthz")
def healthz():
    items = discover_zim_items()
    return jsonify({
        "status": "ok",
        "zim_count": len(items),
        "data_dir": str(DATA_DIR),
        "config_file_exists": CONFIG_FILE.exists(),
    })


@app.route("/static-data/<path:subpath>")
def serve_data_file(subpath: str):
    """A /data/maps/*.pmtiles és hasonlók kiszolgálása.
    A pmtiles HTTP range request-eket kér — a Flask dev/waitress
    alapból támogatja a send_from_directory-val.
    """
    safe_dir = DATA_DIR.resolve()
    target = (safe_dir / subpath).resolve()
    if not str(target).startswith(str(safe_dir)):
        abort(403)
    if not target.exists() or not target.is_file():
        abort(404)
    return send_from_directory(safe_dir, subpath, conditional=True)


@app.route("/kiwix/<path:subpath>", methods=["GET", "POST"])
def kiwix_proxy_hint(subpath: str):
    """A landing oldal nem akar Kiwix proxyt megvalósítani — átirányítjuk
    a felhasználót a Kiwix publikus portjára. Így nincs proxy-bug, nincs CSP
    fejfájás, csak egy redirect.
    """
    host = request.host.split(":")[0]
    qs = request.query_string.decode()
    target = f"http://{host}:{KIWIX_PUBLIC_PORT}/{subpath}"
    if qs:
        target += "?" + qs
    return redirect(target, code=302)


if __name__ == "__main__":
    # Helyi fejlesztéshez ; production-ben a waitress fut a Dockerfile-ből.
    app.run(host="0.0.0.0", port=5000, debug=False)
