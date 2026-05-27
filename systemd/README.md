# systemd integráció

Két fájl ebben a mappában:

- `hu-knowledge-ark-update.service` — egyszeri lefutó unit (Type=oneshot), ami
  `make update`-et hív
- `hu-knowledge-ark-update.timer` — heti egyszeri ütemező (vasárnap 04:00)

## Hogyan kapcsold be?

A repo gyökeréből:

```bash
make enable-auto-update
```

Ez:
1. átmásolja a két fájlt `/etc/systemd/system/` alá (sudo-val)
2. a `@ARK_ROOT@` placeholder-t az aktuális repo útvonalára cseréli
3. enableli és elindítja a timer-t

Ellenőrzés:
```bash
systemctl list-timers hu-knowledge-ark-update.timer
journalctl -u hu-knowledge-ark-update.service -n 50 --no-pager
```

## Kikapcsolás

```bash
make disable-auto-update
```

## Miért nincs `enabled` alapból?

A meglepetésszerű letöltéseket el akarjuk kerülni. Lassú netnél vagy
korlátozott sávszélességnél a felhasználó dönthet, mikor frissítsen.

## Egyéni ütemezés

Ha máskor szeretnéd futtatni (pl. naponta vagy hónap elején), szerkeszd a
`/etc/systemd/system/hu-knowledge-ark-update.timer` fájlt `OnCalendar` sorát.
Példák:

```ini
OnCalendar=daily               # minden nap 00:00
OnCalendar=Mon *-*-* 03:00:00  # hétfő hajnal 3
OnCalendar=*-*-01 04:00:00     # minden hónap 1-én 04:00
```

Aztán: `sudo systemctl daemon-reload && sudo systemctl restart hu-knowledge-ark-update.timer`
