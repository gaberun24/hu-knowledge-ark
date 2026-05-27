# hu-knowledge-ark — magas szintű parancsok
#
# Általában csak ezeket használod a mindennapokban:
#   make install            — első beállítás (mappák, .env, image build)
#   make download           — letölti az enabled tartalmakat (~7-8 GB)
#   make up                 — elindítja a stack-et
#   make update             — frissíti a tartalmat (ha új verzió van)
#   make status             — gyors állapot-jelentés
#   make logs               — Docker logok
#   make down               — megáll
#
# Telepítés körüli extrák:
#   make enable-auto-update — heti automata frissítés bekapcsolása (systemd timer)
#   make disable-auto-update
#   make prune              — kikapcsolt / félben hagyott fájlok takarítása

SHELL := /bin/bash
ARK_ROOT := $(shell pwd)

# .env beolvasása (csak megjelenítéshez; a scriptek maguk is olvassák)
ifneq (,$(wildcard .env))
    include .env
    export
endif

DATA_DIR ?= /opt/hu-knowledge-ark/data
KIWIX_PORT ?= 8888
LANDING_PORT ?= 5050

DOCKER_COMPOSE := docker compose

.PHONY: help install download update up down restart logs status prune \
        enable-auto-update disable-auto-update shell pull build clean check

help:  ## Megmutatja az elérhető parancsokat
	@echo "hu-knowledge-ark — elérhető parancsok:"
	@echo
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "Jelenlegi konfig:"
	@echo "  DATA_DIR=$(DATA_DIR)"
	@echo "  KIWIX_PORT=$(KIWIX_PORT)"
	@echo "  LANDING_PORT=$(LANDING_PORT)"

check:  ## Ellenőrzi: van Docker, van .env, írható a DATA_DIR
	@command -v docker >/dev/null 2>&1 || { echo "HIBA: Docker nincs telepítve"; exit 1; }
	@docker compose version >/dev/null 2>&1 || { echo "HIBA: 'docker compose' nem elérhető"; exit 1; }
	@test -f .env || { echo "HIBA: nincs .env, futtass: cp .env.example .env"; exit 1; }
	@test -d "$(DATA_DIR)" || { echo "Megj.: $(DATA_DIR) még nincs, létrehozom"; mkdir -p "$(DATA_DIR)/zim" "$(DATA_DIR)/maps"; }
	@touch "$(DATA_DIR)/.write_test" 2>/dev/null && rm "$(DATA_DIR)/.write_test" || { echo "HIBA: nem tudok írni ide: $(DATA_DIR) — ellenőrizd a PUID/PGID-et az .env-ben"; exit 1; }
	@command -v python3 >/dev/null 2>&1 || { echo "FIGYELEM: a host gépen nincs python3 — a YAML parser nem fog futni. Telepítsd: apt-get install -y python3 python3-yaml"; exit 1; }
	@python3 -c "import yaml" 2>/dev/null || { echo "FIGYELEM: nincs python3-yaml modul. Telepítés: apt-get install -y python3-yaml  (vagy: pip install pyyaml)"; exit 1; }
	@echo "[✓] minden alap rendben"

install: check pull build  ## Első beállítás (mappák, image build, futtatható scriptek)
	@chmod +x scripts/*.sh
	@echo
	@echo "[✓] Telepítés kész."
	@echo "    Következő lépés:  make download   (tartalom letöltése, ~7-8 GB)"
	@echo "    Aztán:           make up         (szolgáltatások indítása)"

pull:  ## Docker image-ek lekérése (kiwix-tools, pmtiles)
	@$(DOCKER_COMPOSE) pull kiwix || true
	@docker pull ghcr.io/kiwix/kiwix-tools:latest || true
	@docker pull protomaps/go-pmtiles:latest || true

build:  ## Landing image build
	@$(DOCKER_COMPOSE) build landing

download:  ## Tartalom letöltése (vagy hiányzó pótlása) — első futáskor ~7-8 GB
	@./scripts/download.sh

update:  ## Új verziók ellenőrzése és letöltése
	@./scripts/update.sh

prune:  ## Kikapcsolt / félben hagyott / régi verziók törlése
	@./scripts/prune.sh

up:  ## Stack indítása
	@$(DOCKER_COMPOSE) up -d
	@echo
	@echo "[✓] Elérhető:"
	@echo "    Landing:  http://$$(hostname -I 2>/dev/null | awk '{print $$1}' || hostname):$(LANDING_PORT)/"
	@echo "    Kiwix:    http://$$(hostname -I 2>/dev/null | awk '{print $$1}' || hostname):$(KIWIX_PORT)/"

down:  ## Stack leállítása
	@$(DOCKER_COMPOSE) down

restart:  ## Stack újraindítása
	@$(DOCKER_COMPOSE) restart

logs:  ## Docker logok (Ctrl-C-vel kilépsz)
	@$(DOCKER_COMPOSE) logs -f --tail=100

status:  ## Konténerek + tartalom állapota
	@echo "=== Konténerek ==="
	@$(DOCKER_COMPOSE) ps
	@echo
	@echo "=== Adatkönyvtár: $(DATA_DIR) ==="
	@du -sh "$(DATA_DIR)" 2>/dev/null || echo "(még nem létezik)"
	@if [[ -d "$(DATA_DIR)/zim" ]]; then \
	    echo "  ZIM fájlok:"; \
	    ls -lh "$(DATA_DIR)/zim/"*.zim 2>/dev/null | awk '{printf "    %-12s  %s\n", $$5, $$NF}' || echo "    (nincs)"; \
	fi
	@if [[ -d "$(DATA_DIR)/maps" ]]; then \
	    echo "  Térkép:"; \
	    ls -lh "$(DATA_DIR)/maps/"*.pmtiles 2>/dev/null | awk '{printf "    %-12s  %s\n", $$5, $$NF}' || echo "    (nincs)"; \
	fi
	@echo
	@if systemctl list-timers hu-knowledge-ark-update.timer >/dev/null 2>&1; then \
	    echo "=== Automata frissítés ==="; \
	    systemctl list-timers --no-pager hu-knowledge-ark-update.timer; \
	fi

shell:  ## Belépés a kiwix konténerbe (debughoz)
	@$(DOCKER_COMPOSE) exec kiwix /bin/sh

enable-auto-update:  ## Heti automata frissítés bekapcsolása (sudo szükséges)
	@echo "Symlink: $(ARK_ROOT)/systemd/hu-knowledge-ark-update.* → /etc/systemd/system/"
	@sudo cp -v systemd/hu-knowledge-ark-update.service /etc/systemd/system/
	@sudo cp -v systemd/hu-knowledge-ark-update.timer /etc/systemd/system/
	@sudo sed -i "s|@ARK_ROOT@|$(ARK_ROOT)|g" /etc/systemd/system/hu-knowledge-ark-update.service
	@sudo systemctl daemon-reload
	@sudo systemctl enable --now hu-knowledge-ark-update.timer
	@echo
	@sudo systemctl list-timers hu-knowledge-ark-update.timer --no-pager
	@echo "[✓] Automata frissítés bekapcsolva — heti egyszer fut."

disable-auto-update:  ## Heti automata frissítés kikapcsolása
	@sudo systemctl disable --now hu-knowledge-ark-update.timer || true
	@sudo rm -f /etc/systemd/system/hu-knowledge-ark-update.service \
	            /etc/systemd/system/hu-knowledge-ark-update.timer
	@sudo systemctl daemon-reload
	@echo "[✓] Automata frissítés kikapcsolva."

clean:  ## NAGY TAKARÍTÁS: konténerek + image + DATA_DIR törlése (kérdez először)
	@echo "FIGYELEM: ez törli a stack-et és a tartalmat is."
	@echo "DATA_DIR: $(DATA_DIR)"
	@read -p "Biztos? (igen/nem): " ans && [ "$$ans" = "igen" ]
	@$(DOCKER_COMPOSE) down -v --rmi local
	@rm -rf "$(DATA_DIR)"
	@echo "[✓] Letakarítva."
