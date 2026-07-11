# claude-sandbox

Exécution de Claude Code dans un conteneur Docker isolé, avec système de fichiers en lecture seule, capacités Linux réduites au minimum et volumes montés depuis le disque hôte.

**Repos liés :**
- Ce repo : https://github.com/senseicoder/claude-sandbox
- Services MCP (Gmail, Drive, Calendar, Jira, IMAP, Freebox, infra) : https://github.com/senseicoder/mcp-services

## Objectif de sécurité

En cas de compromission de l'instance Claude Code (injection de prompt, MCP malveillant, outil détourné), le conteneur limite les dégâts :

- le système de fichiers du conteneur est **en lecture seule** — aucune écriture possible hors volumes explicitement montés
- le processus tourne en **utilisateur non privilégié** (uid 1000, sans sudo)
- **toutes les capacités Linux sont supprimées** (`--cap-drop ALL`) — pas de bind port < 1024, pas de montage, pas de manipulation de processus
- pas de `--privileged`
- **réseau limité aux seuls services MCP** (`mcp-sandbox-net`, internal) — aucun accès Internet direct, aucun accès à un service du poste hôte. Seule sortie autorisée : `api.anthropic.com`, via un proxy dédié (`egress-proxy`). Voir `docs/adr/ADR-001-isolation-reseau-mcp-net.md`.

## Ce qui est accessible depuis le conteneur

| Volume hôte | Point de montage | Mode |
|---|---|---|
| `~/.claude/` | `/home/user/.claude/` | rw — config, mémoire, sessions |
| `config/mcp.json` | `/home/user/.claude.json` | ro — MCP servis en réseau par `mcp-services` |
| `~/www/` | `/home/cedric/www/` | rw — code, chemin identique à l'hôte (voir ADR-003) |
| `~/Sync/Central/Dossiers/obsidian/` | `/home/cedric/Sync/Central/Dossiers/obsidian/` | rw — vault Obsidian, chemin identique à l'hôte |
| `~/Work/cnt/claude-sandbox/` | `/exchange/` | rw — dossier d'échange (convention `~/Work/cnt/<nom-conteneur>`, réutilisable pour d'autres sandbox) |

Les répertoires système du conteneur (`/usr`, `/bin`, `/etc`, `/lib`) sont en lecture seule.
Les écritures nécessaires au runtime (logs, tmp) sont servies par des tmpfs en mémoire.

**Pourquoi des chemins identiques à l'hôte pour `www` et le vault Obsidian** : de nombreux fichiers (`CLAUDE.md`, pages wiki, `orga.perso.md`/`orga.claude.md`) référencent des chemins absolus entre eux ou vers des scripts. Les monter sous un nom générique (`/workspace`) casserait ces références dès que Claude les suit à l'intérieur du sandbox.

## Prérequis

- Docker ≥ 20.10
- `mcp-services` déjà lancé (au moins les services référencés dans `config/mcp.json`) — `claude-sandbox` ne fait que les consommer, il ne les démarre pas
- Dossiers à créer sur l'hôte avant le premier lancement :
  ```bash
  mkdir -p ~/Work/cnt/claude-sandbox
  ```
- Clé API Anthropic dans l'environnement : `export ANTHROPIC_API_KEY=sk-...`

## Utilisation rapide

```bash
# Construire les images (claude + egress-proxy)
docker compose -f docker/compose.yml build

# Lancer une session Claude Code
./scripts/run.sh
```

## Architecture

```
claude-sandbox/
├── docker/
│   ├── Dockerfile          # image claude, non privilégiée, read-only
│   ├── compose.yml         # volumes, réseaux, caps, security opts
│   └── egress-proxy/
│       ├── Dockerfile      # squid minimal
│       └── squid.conf      # ACL : uniquement api.anthropic.com
├── docs/adr/                # décisions d'architecture (ADR-001 à ADR-003)
├── mcp/
│   └── README.md
├── scripts/
│   └── run.sh               # wrapper de lancement
└── CLAUDE.md                 # instructions pour Claude dans le conteneur
```

## Modèle de menace

Ce sandbox protège contre :
- **Écriture non autorisée** sur le disque hôte hors volumes montés
- **Escalade de privilèges** via capabilities Linux
- **Exfiltration réseau** — isolation totale sauf `mcp-net` interne et `api.anthropic.com` via proxy dédié
- **Persistence** : le conteneur est éphémère, seuls les volumes montés persistent

Ce sandbox ne protège **pas** contre :
- Exfiltration de données via les volumes montés (lecture/écriture autorisée sur `~/www` et le vault Obsidian entiers)
- Compromission via un MCP ayant accès réseau (les services `mcp-services` gardent, eux, un accès Internet propre)

Voir `SECURITY.md` pour le détail risque par risque.
