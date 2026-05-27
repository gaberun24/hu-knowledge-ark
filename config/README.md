# A `content.yaml` szerkesztése

Itt mondod meg az arknak, hogy mit szeretnél letölteni és megtartani.

## Tipikus változtatások

**Kikapcsolni egy tételt** (pl. nem érdekel a Wikiquote):
```yaml
- id: wikiquote_hu
  ...
  enabled: false   # ← ezt írd át
```

A következő `make update` futáskor a szolgáltatás nem tölti le, és ha
korábban letöltötted, a `make prune` letakarítja.

**Átkapcsolni a kis Wikipédiára** (lassú net / kis disk):
```yaml
- id: wikipedia_hu
  enabled: false   # nagy verzió KI
- id: wikipedia_hu_nopic
  enabled: true    # kis verzió BE
```

**Másik térkép-régiót szeretnél** (pl. egész Magyarország):
```yaml
map:
  bbox: "16.10,45.70,22.90,48.60"   # egész HU, ~1.2 GB
  output_name: "magyarorszag.pmtiles"
```

**Új ZIM tételt hozzátenni** (pl. magyar Wikinews ha valaha kijönne):
```yaml
- id: wikinews_hu
  pattern: "wikinews_hu_all_*.zim"
  base_url: "https://download.kiwix.org/zim/wikinews/"
  title: "Magyar Wikihír"
  category: "hirek"
  enabled: true
```

## Mezők

| Mező | Kötelező | Mit jelent |
|---|---|---|
| `id` | igen | Egyedi azonosító, fájlnév-prefixként és library-ben használja |
| `pattern` | igen | A fájlnév mintája (`*` joker) — a script ez alapján keresi a legfrissebbet |
| `base_url` | igen | A Kiwix server-en lévő könyvtár, ahol a fájl van |
| `title` | igen | A landing oldalon megjelenő név |
| `description` | nem | Rövid leírás a landing kártyán |
| `category` | nem | Csoportosítás: `altalanos`, `nyelv`, `oktatas`, `irodalom`, `terkep`, … |
| `icon` | nem | Ikon neve a landing oldalon (statikus mapping) |
| `enabled` | igen | `true`/`false` — be vagy ki van kapcsolva |

## Honnan tudom milyen ZIM van?

A [download.kiwix.org/zim/](https://download.kiwix.org/zim/) oldalon
böngészheted. A magyar nyelvű fájlokat a `_hu_` infix árulja el a fájlnévben.
