# claude-sandbox

Exécution de Claude Code dans un conteneur Docker isolé, avec système de fichiers en lecture seule, capacités Linux réduites au minimum et volumes montés depuis le disque hôte.

**Repos liés :**
- Ce repo : https://github.com/senseicoder/claude-sandbox
- MCP infra lecture seule : https://github.com/senseicoder/mcp-infra-readonly

## Objectif de sécurité

En cas de compromission de l'instance Claude Code (injection de prompt, MCP malveillant, outil détourné), le conteneur limite les dégâts :

- le système de fichiers du conteneur est **en lecture seule** — aucune écriture possible hors volumes explicitement montés
- le processus tourne en **utilisateur non privilégié** (uid 1000, sans sudo)
- **toutes les capacités Linux sont supprimées** (`--cap-drop ALL`) — pas de bind port < 1024, pas de montage, pas de manipulation de processus
- pas de `--privileged`
- accès réseau limité à ce qui est strictement nécessaire

## Ce qui est accessible depuis le conteneur

| Volume hôte | Point de montage | Mode |
|---|---|---|
| `~/.claude/` | `/home/user/.claude/` | rw — config, mémoire, sessions |
| `~/.ssh/` | `/home/user/.ssh/` | ro — clés SSH pour mcp-infra-readonly |
| `config/mcp.json` | `/home/user/.claude.json` | ro — configuration des MCP (Gmail, GDrive, Calendar, infra) |
| `~/.config/google-drive-mcp/` | `/home/user/.config/google-drive-mcp/` | rw — tokens OAuth Google Drive |
| `~/.config/google-calendar-mcp/` | `/home/user/.config/google-calendar-mcp/` | rw — tokens OAuth Google Calendar |
| `~/www/c/` (ou autre dossier code) | `/workspace/` | rw — code à éditer |
| `~/claude-exchange/` | `/exchange/` | rw — dossier d'échange fichiers |

Les répertoires système du conteneur (`/usr`, `/bin`, `/etc`, `/lib`) sont en lecture seule.
Les écritures nécessaires au runtime (logs, tmp) sont servies par des tmpfs en mémoire.

## Prérequis

- Docker ≥ 20.10
- Claude Code installé localement (pour construire l'image)
- Dossiers à créer sur l'hôte avant le premier lancement :
  ```bash
  mkdir -p ~/claude-exchange
  mkdir -p ~/.config/google-drive-mcp
  mkdir -p ~/.config/google-calendar-mcp
  ```
- Fichier de credentials Google Drive dans `~/.config/google-drive-mcp/gcp-oauth.keys.json` (voir `mcp/README.md`)
- Clé API Anthropic dans l'environnement : `export ANTHROPIC_API_KEY=sk-...`

## Utilisation rapide

```bash
# Construire l'image
docker build -t claude-sandbox docker/

# Lancer une session Claude Code
./scripts/run.sh

# Ou avec un dossier de code spécifique
WORKSPACE=~/www/e/mon-projet ./scripts/run.sh
```

## Architecture

```
claude-sandbox/
├── docker/
│   ├── Dockerfile      # image non privilégiée, read-only
│   └── compose.yml     # volumes, caps, security opts
├── mcp/
│   └── README.md       # comment les MCP sont injectés dans le conteneur
├── scripts/
│   └── run.sh          # wrapper de lancement
└── CLAUDE.md           # instructions pour Claude dans le conteneur
```

## Modèle de menace

Ce sandbox protège contre :
- **Écriture non autorisée** sur le disque hôte hors volumes montés
- **Escalade de privilèges** via capabilities Linux
- **Pivot réseau** (via restrictions réseau optionnelles dans compose.yml)
- **Persistence** : le conteneur est éphémère, seuls les volumes montés persistent

Ce sandbox ne protège **pas** contre :
- Exfiltration de données via les volumes montés (lecture autorisée)
- Appels réseau sortants (à restreindre via iptables ou réseau Docker dédié si nécessaire)
- Compromission via un MCP ayant accès réseau
