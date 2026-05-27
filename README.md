# 🛟 Magyar Tudásbárka (hu-knowledge-ark)

> **Otthoni offline tudásbázis magyar nyelven.** Áramszünet, internet-kimaradás vagy egyszerűen kíváncsiság esetén — bármikor elérhető a saját hálózatodról, mindenféle felhő nélkül.

A magyar Wikipédia, Wikiszótár, Wikikönyvek, Wikidézet, Wikiforrás és egy testre szabható OpenStreetMap-alapú offline térkép — egy összefogott Docker stack-be csomagolva, beépített közös keresővel.

---

## Mit kapsz?

| Tartalom | Kb. méret | Mit tud |
|---|---|---|
| Magyar Wikipédia (teljes) | ~6 GB | Általános tudás, történelem, természettudományok, … |
| Magyar Wikiszótár | ~150 MB | Szótár, etimológia, ragozási minták |
| Magyar Wikikönyvek | ~100 MB | Tankönyvek, gyógynövény-lista, főzés, programozás |
| Magyar Wikidézet | ~50 MB | Idézetek, közmondások |
| Magyar Wikiforrás | ~500 MB | Klasszikus szövegek, irodalom |
| Offline térkép (Zala+környék) | ~300 MB | OpenStreetMap-alapú vektoros térkép, böngészőben |

**Összesen kb. 7-8 GB** — egy 16 GB-os pendrive-ra is ráfér.

A tartalom a [Wikimédia](https://hu.wikipedia.org) projektekből származik, [Creative Commons](https://creativecommons.org/licenses/by-sa/4.0/deed.hu) licenc alatt. A térkép a [Protomaps](https://protomaps.com) napi planet-build-jeiből készül, az [OpenStreetMap](https://www.openstreetmap.org/copyright) közreműködőitől.

---

## Mire való?

- Vidéki ingatlan, nyaraló — ahol bizonytalan az internet
- Vészhelyzeti felkészülés — áramszünet, hálózatkimaradás
- Iskola, könyvtár — gyerekek kutathatnak külső adatforgalom nélkül
- Hosszú utazás — autóbusz, hajó, repülő
- Egyszerűen szuverén informatika — saját szerver, saját adat

---

## Mire **nem** való?

- Nem helyettesíti az orvost, gyógyszertárat, ügyvédet vagy hivatalt.
- Nem live, nem real-time — a tartalom egy adott időpontban befagyasztott pillanatkép.
- Nem érdemes mobiltelefon belső tárhelyén tartani (a 7-8 GB-os Wikipédia túl nagy hozzá) — egy mini PC, NAS, Raspberry Pi a jó cél.

---

## Mire van szükséged?

| Komponens | Minimum | Javaslat |
|---|---|---|
| **Gép** | Bármi amin fut Docker | Raspberry Pi 4/5, mini PC, NAS, régi laptop |
| **Tárhely** | 10 GB szabad | 32 GB+ ha a térkép is kell |
| **RAM** | 1 GB | 2 GB |
| **OS** | Linux (Debian/Ubuntu/Pi OS/…), macOS, Windows WSL | Linux |
| **Szoftver** | Docker + Docker Compose, `make`, `python3`+pyyaml, `wget`, `curl` | — |

> 💡 Synology vagy TrueNAS NAS-on is működik, csak állítsd a `PUID/PGID`-et a megosztás tulajdonosára.

---

## 🚀 Telepítés 5 percben

```bash
# 1. Klónozd a repot
git clone https://github.com/gaberun24/hu-knowledge-ark.git
cd hu-knowledge-ark

# 2. Konfiguráld
cp .env.example .env
$EDITOR .env       # állítsd be: DATA_DIR, PUID, PGID, portok

# 3. Telepítés (image build, mappák, írási jog ellenőrzése)
make install

# 4. Tartalom letöltése (~7-8 GB, kb. 5-15 perc, hálózattól függ)
make download

# 5. Stack indítása
make up
```

Ezután a böngésződből:
- **Landing oldal**: `http://<géped-ip>:5050`
- **Közvetlen Kiwix UI**: `http://<géped-ip>:8888`

> 💡 Ha nem tudod a géped IP-jét: `hostname -I` (Linux) vagy `ifconfig` (macOS).

---

## Mindennapi használat

| Mit szeretnél? | Parancs |
|---|---|
| Megnyitni böngészőben | `http://<géped-ip>:5050` |
| Frissíteni új verzióra | `make update` |
| Megnézni állapotot | `make status` |
| Logokat nézni | `make logs` (Ctrl-C-vel kilépsz) |
| Megállítani | `make down` |
| Újraindítani | `make restart` |
| Letakarítani régi fájlokat | `make prune` |
| Az összes parancsot | `make help` |

---

## Frissítések

Az új Wikipédia verziók kb. **havonta** jelennek meg a [Kiwix-en](https://download.kiwix.org/zim/wikipedia/). Két lehetőséged van:

### Kézi frissítés (alapértelmezett)

```bash
make update
```

Ez:
1. Lekéri a Kiwix listáját
2. Összehasonlítja a meglévővel
3. Letölt amit kell, SHA-256 hash-szel ellenőriz
4. Régi verziókat töröl
5. Újraindítja a Kiwix konténert

### Automata heti frissítés (opcionális)

```bash
make enable-auto-update    # vasárnap 04:00-kor fut
```

Megnézheted:
```bash
systemctl list-timers hu-knowledge-ark-update.timer
journalctl -u hu-knowledge-ark-update.service -n 50
```

Kikapcsolás:
```bash
make disable-auto-update
```

---

## Testre szabás

A `config/content.yaml` az **egyetlen** fájl amit szerkesztened kell ha mást szeretnél. Részletek: [`config/README.md`](config/README.md).

**Példák:**

Csak a kis Wikipédiát szeretnéd (1.5 GB):
```yaml
- id: wikipedia_hu
  enabled: false
- id: wikipedia_hu_nopic
  enabled: true
```

Egész Magyarországot a térképen:
```yaml
map:
  bbox: "16.10,45.70,22.90,48.60"
  output_name: "magyarorszag.pmtiles"
```

Egy tételt kihagyni:
```yaml
- id: wikiquote_hu
  enabled: false
```

A változtatások után:
```bash
make download   # új tartalom letöltése
make prune      # kikapcsolt tartalom takarítása
```

---

## Felépítés (architektúra)

```
        ┌─────────────────────────────────┐
        │     Böngésződ (LAN)             │
        └────────┬──────────────┬─────────┘
                 │              │
         :5050 (landing)  :8888 (kiwix)
                 │              │
        ┌────────▼──┐   ┌───────▼──────────┐
        │  landing  │   │  kiwix-serve     │
        │ (Flask)   │   │ (ZIM + Xapian    │
        │           │   │  keresés)        │
        └────────┬──┘   └───────┬──────────┘
                 │              │
                 └──────┬───────┘
                        │
              ┌─────────▼──────────┐
              │   DATA_DIR         │
              │ ├── zim/*.zim      │
              │ ├── library.xml    │
              │ └── maps/*.pmtiles │
              └────────────────────┘
```

- **kiwix-serve**: ZIM fájlokat szolgál, beépített Xapian keresővel (magyar nyelvű tokenizálás)
- **landing**: vékony Flask app, kategória-kártyák + a térkép viewer
- **DATA_DIR**: minden tartalom egy helyen — könnyen menthető, áthelyezhető

---

## Hibakeresés

### "Nem tudok írni a DATA_DIR-be"
Az `.env`-ben a `PUID/PGID` nem egyezik a könyvtár tulajdonosával. Nézd meg:
```bash
ls -la $(grep DATA_DIR .env | cut -d= -f2)
id    # a saját UID/GID-ed
```

### "make download lassú / 0 byte után megáll"
A Kiwix szervere néha lassú peak időszakban. Próbáld egy [tükörről](https://wiki.kiwix.org/wiki/Content_in_all_languages#Mirrors), pl.:
```yaml
base_url: "https://ftp.fau.de/kiwix/zim/wikipedia/"
```

### "A térkép nem jelenik meg"
A pmtiles fájl HTTP range request-eket vár — egyes proxyk (régi nginx, Cloudflare néhány konfigja) nem továbbítják. Próbáld közvetlenül a portról: `http://<géped-ip>:5050/map`.

### "Az új ZIM-em nem jelenik meg"
A library.xml újragenerálása ennyit kér:
```bash
./scripts/build-library.sh
make restart
```

---

## Cloudflare tunnel, fordított proxy

Az alapértelmezett konfig **csak LAN-on** elérhető. Ha kívülről is szeretnéd publikálni:

- **Cloudflare Tunnel**: csinálj egy második docker-compose.override.yml fájlt egy `cloudflared` service-szel, és [add a tunnel-edet](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/get-started/create-local-tunnel/). Csak akkor, ha tudod mit csinálsz — a Wikipédia rajongóid felelnek a sávszélért.
- **Reverse proxy** (Caddy/nginx/Traefik): irányítsd a domain-edet a `LANDING_PORT`-ra. A Kiwix-et NEM kell külön publikálni — a landing rajta keresztül használja.

Ezek nem jönnek a repo-val, mert mindenki más környezetben van.

---

## Hozzájárulás

Pull requestek szívesen jönnek! Különösen:
- További magyar tartalom-forrásokra mutató tippek
- Hibák javítása
- A README magyarításának pontosítása
- Más NAS-okra (Synology, QNAP, TrueNAS) telepítési tapasztalatok

---

## Licenc

A **kód** [MIT](LICENSE) — bármire használhatod.

A **tartalom** (Wikipédia, OpenStreetMap, stb.) a saját licencei alatt áll, általában CC BY-SA. Ezt a repo csak letölti és helyileg szolgálja, nem birtokolja és nem ad rá garanciát.

---

## Köszönet

- A [Kiwix](https://kiwix.org) projektnek a ZIM formátumért és a kiwix-tools-ért
- A [Protomaps](https://protomaps.com) projektnek a pmtiles formátumért és a free planet build-ekért
- A [Wikimédia](https://wikipedia.org) közösségnek a magyar Wikipédiáért és társprojekteiért
- Az [OpenStreetMap](https://openstreetmap.org) közreműködőinek a térképadatokért
