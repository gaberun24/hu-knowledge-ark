"""
Háttér-letöltő logika a hu-knowledge-ark landingnek.

Önállóan futtatható (debug céllal), de elsősorban az app.py importálja és
egy threading.Thread-ben hívja meg a `run_update_job()` függvényt.

A fő munka:
  1. content.yaml beolvasása
  2. minden enabled ZIM-re: legfrissebb távoli verzió keresése HTML index parse-szal
  3. ami régi vagy hiányzik: letöltés (HTTP), SHA256 hash check
  4. régi verziók törlése a keep_versions szerint
  5. library.xml újraépítése a kiwix-tools image-mel a Docker daemon-on át
  6. a hu-ark-kiwix konténer restartolása

A progress globális JobState objektumon át követhető (thread-safe).
"""
from __future__ import annotations

import hashlib
import os
import re
import shutil
import tempfile
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

import requests
import yaml

DATA_DIR = Path(os.environ.get("DATA_DIR", "/data"))
# A host gépi útvonal — fontos, mert a docker daemon a host path-okat várja,
# nem a konténerbelit. Ha nincs külön megadva, feltételezzük, hogy a kettő
# megegyezik (host gépen futtatva, nem konténerből).
DATA_DIR_HOST = os.environ.get("DATA_DIR_HOST", str(DATA_DIR))
CONFIG_FILE = Path(os.environ.get("CONFIG_FILE", "/app/config/content.yaml"))
KIWIX_CONTAINER = os.environ.get("KIWIX_CONTAINER", "hu-ark-kiwix")
PUID = os.environ.get("PUID", "1000")
PGID = os.environ.get("PGID", "1000")


@dataclass
class JobState:
    """Háttérben futó letöltés állapota."""
    running: bool = False
    started_at: float = 0.0
    finished_at: float = 0.0
    current_step: str = ""
    log: list[str] = field(default_factory=list)
    error: Optional[str] = None
    items_total: int = 0
    items_done: int = 0
    current_item_progress: float = 0.0  # 0.0 - 1.0 a jelenlegi fájl letöltési aránya
    current_item_name: str = ""

    def to_dict(self) -> dict:
        return {
            "running": self.running,
            "started_at": self.started_at,
            "finished_at": self.finished_at,
            "current_step": self.current_step,
            "log": self.log[-50:],  # csak az utolsó 50 sor
            "error": self.error,
            "items_total": self.items_total,
            "items_done": self.items_done,
            "current_item_progress": self.current_item_progress,
            "current_item_name": self.current_item_name,
        }


# Globális, thread-safe állapot
_job = JobState()
_job_lock = threading.Lock()


def get_state() -> dict:
    with _job_lock:
        return _job.to_dict()


def _say(msg: str) -> None:
    print(f"[downloader] {msg}", flush=True)
    with _job_lock:
        _job.log.append(msg)


def _load_config() -> dict:
    with CONFIG_FILE.open(encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


def _find_latest_remote(base_url: str, pattern: str, user_agent: str) -> Optional[str]:
    """A pattern-nek megfelelő legfrissebb fájlnév a kiwix.org HTML listájában."""
    regex_str = re.escape(pattern).replace(r"\*", "[^\"]*")
    regex = re.compile(regex_str)

    resp = requests.get(base_url, headers={"User-Agent": user_agent}, timeout=30)
    resp.raise_for_status()

    matches = sorted(set(regex.findall(resp.text)), reverse=True)
    return matches[0] if matches else None


def _download_file(url: str, dst: Path, user_agent: str) -> None:
    """Letölt egy URL-t a dst-be, miközben frissíti a job progress-t.
    Atomic: .partial-ba ír, aztán mv."""
    tmp = dst.with_suffix(dst.suffix + ".partial")
    headers = {"User-Agent": user_agent}

    with requests.get(url, headers=headers, stream=True, timeout=300) as r:
        r.raise_for_status()
        total = int(r.headers.get("Content-Length", 0))
        downloaded = 0
        with tmp.open("wb") as f:
            for chunk in r.iter_content(chunk_size=1024 * 1024):
                if chunk:
                    f.write(chunk)
                    downloaded += len(chunk)
                    if total:
                        with _job_lock:
                            _job.current_item_progress = downloaded / total

    tmp.rename(dst)


def _verify_sha256(file_path: Path, expected: str) -> bool:
    h = hashlib.sha256()
    with file_path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest().lower() == expected.lower()


def _rebuild_library_via_docker() -> None:
    """A kiwix-tools image-mel egyszeri konténerként újraépíti a library.xml-t.
    Aztán restartolja a kiwix konténert."""
    import docker  # lazy import
    client = docker.from_env()

    _say("Library.xml újraépítése (kiwix-manage)…")

    # A meglévő library.xml-t töröljük, aztán minden ZIM-re lefuttatunk egy add-et.
    # `find` használata glob helyett — robusztusabb a busybox sh-en, és a
    # docker-py command-átadásnál sem okoz quoting fejfájást.
    cmd = (
        "rm -f /data/library.xml && "
        "find /data/zim -maxdepth 1 -name '*.zim' -print "
        "-exec kiwix-manage /data/library.xml add {} \\; && "
        "echo 'library.xml elkészült'"
    )
    container = client.containers.run(
        image="ghcr.io/kiwix/kiwix-tools:latest",
        # A kiwix-tools image entrypointja dumb-init, ami nem értelmezi a
        # shell metakaraktereket. Felülírjuk: az ENTIRE shell hívás a command-ba.
        entrypoint="/bin/sh",
        command=["-c", cmd],
        volumes={DATA_DIR_HOST: {"bind": "/data", "mode": "rw"}},
        user=f"{PUID}:{PGID}",
        remove=True,
        detach=False,
        stdout=True,
        stderr=True,
    )
    if isinstance(container, bytes):
        out = container.decode("utf-8", errors="replace")
        for line in out.splitlines():
            _say("  " + line)

    _say(f"{KIWIX_CONTAINER} konténer újraindítása…")
    try:
        kiwix = client.containers.get(KIWIX_CONTAINER)
        kiwix.restart(timeout=10)
        _say("Kiwix konténer újraindult.")
    except docker.errors.NotFound:
        _say(f"FIGYELEM: '{KIWIX_CONTAINER}' konténer nem található. Lehet, hogy le van állítva — indítsd: make up")


def _run_update() -> None:
    """A frissítés tényleges logikája. Belül fut a thread-en."""
    cfg = _load_config()
    settings = cfg.get("settings", {})
    user_agent = settings.get("user_agent", "hu-knowledge-ark/1.0")
    keep_versions = int(settings.get("keep_versions", 1))

    zim_dir = DATA_DIR / "zim"
    zim_dir.mkdir(parents=True, exist_ok=True)

    enabled_sources = [s for s in cfg.get("zim_sources", []) if s.get("enabled")]

    with _job_lock:
        _job.items_total = len(enabled_sources)
        _job.items_done = 0

    if not enabled_sources:
        _say("Nincs egyetlen enabled forrás sem.")
        return

    for src in enabled_sources:
        sid = src["id"]
        pattern = src["pattern"]
        base_url = src["base_url"]
        title = src.get("title", sid)

        with _job_lock:
            _job.current_step = f"Ellenőrzés: {title}"
            _job.current_item_name = title
            _job.current_item_progress = 0.0

        _say(f"--- {title} ({sid}) ---")
        try:
            remote = _find_latest_remote(base_url, pattern, user_agent)
        except Exception as e:
            _say(f"  HIBA index olvasásánál: {e}")
            with _job_lock:
                _job.items_done += 1
            continue

        if not remote:
            _say(f"  Nem találtam {pattern}-nek megfelelő fájlt itt: {base_url}")
            with _job_lock:
                _job.items_done += 1
            continue

        local_path = zim_dir / f"{sid}__{remote}"
        if local_path.exists() and local_path.stat().st_size > 1_000_000:
            _say(f"  Már megvan: {local_path.name} ({local_path.stat().st_size // 1024 // 1024} MB)")
            with _job_lock:
                _job.items_done += 1
            continue

        # Régi verziók (az új letöltés ELŐTTI állapotban)
        existing = sorted(zim_dir.glob(f"{sid}__*.zim"), reverse=True)

        with _job_lock:
            _job.current_step = f"Letöltés: {title}"
        _say(f"  Letöltés: {base_url}{remote}")
        try:
            _download_file(base_url + remote, local_path, user_agent)
        except Exception as e:
            _say(f"  HIBA letöltésnél: {e}")
            with _job_lock:
                _job.items_done += 1
            continue

        # SHA256 ha van
        try:
            sha_resp = requests.get(base_url + remote + ".sha256",
                                    headers={"User-Agent": user_agent}, timeout=30)
            if sha_resp.ok:
                expected = sha_resp.text.split()[0]
                with _job_lock:
                    _job.current_step = f"Hash ellenőrzés: {title}"
                _say(f"  Hash ellenőrzés…")
                if not _verify_sha256(local_path, expected):
                    _say(f"  HIBA: SHA256 nem egyezik. Törlöm.")
                    local_path.unlink()
                    with _job_lock:
                        _job.items_done += 1
                    continue
                _say(f"  Hash OK.")
        except Exception as e:
            _say(f"  Hash check kihagyva: {e}")

        size_mb = local_path.stat().st_size // 1024 // 1024
        _say(f"  Új fájl: {local_path.name} ({size_mb} MB)")

        # Régi verziók takarítása
        if len(existing) >= keep_versions:
            for old in existing[keep_versions - 1:]:
                _say(f"  Régi törlése: {old.name}")
                old.unlink(missing_ok=True)

        with _job_lock:
            _job.items_done += 1

    # Térkép — pmtiles. Egyelőre szóljunk, hogy ezt parancssorból csináljuk
    # (a go-pmtiles bináris az image-ben jobban kezel range request-eket;
    # nem akarjuk a landing-be replikálni a teljes pmtiles olvasót).
    map_cfg = cfg.get("map", {}) or {}
    if map_cfg.get("enabled"):
        map_file = DATA_DIR / "maps" / map_cfg.get("output_name", "")
        if not map_file.exists():
            _say("[megjegyzés] A térkép pmtiles még nincs. Futtasd parancssorból: "
                 "./scripts/pmtiles-extract.sh — a webből nem tölthető hatékonyan.")

    with _job_lock:
        _job.current_step = "Library újraépítése"

    _rebuild_library_via_docker()


def run_update_job() -> bool:
    """Elindít egy frissítési thread-et, ha még nem fut.
    Returns True ha új job indult, False ha már futott egy.
    """
    global _job
    with _job_lock:
        if _job.running:
            return False
        _job = JobState(running=True, started_at=time.time())

    def _worker() -> None:
        try:
            _run_update()
        except Exception as e:
            _say(f"VÉGZETES HIBA: {e}")
            with _job_lock:
                _job.error = str(e)
        finally:
            with _job_lock:
                _job.running = False
                _job.finished_at = time.time()
                _job.current_step = "Kész."

    t = threading.Thread(target=_worker, daemon=True, name="ark-updater")
    t.start()
    return True


if __name__ == "__main__":
    # Standalone teszthez
    run_update_job()
    while True:
        st = get_state()
        print(st)
        if not st["running"]:
            break
        time.sleep(2)
