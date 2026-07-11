# MCP dans le conteneur

Les MCP sont configurés via `config/mcp.json` à la racine du repo, monté en lecture seule comme `/home/user/.claude.json` dans le conteneur. Claude Code lit ce fichier au démarrage comme sa configuration MCP globale.

Depuis le 2026-07-11, **tous les MCP externes sont servis en réseau par `mcp-services`** (repo séparé) — plus aucun MCP natif (npm) ni credential dans l'image `claude-sandbox`. Voir `docs/adr/ADR-002-migration-mcp-services.md`.

## Architecture

```
Hôte                                   Conteneur claude
─────────────────────────              ─────────────────────────────────
config/mcp.json (ce repo) ──── ro ──▶  /home/user/.claude.json
                                        (référence les services ci-dessous
                                         par leur nom DNS Docker)

mcp-sandbox-net (Docker, internal)  ◀──▶  mcp-google-pro:8001/8002/8003
                                           mcp-google-perso:8004/8005/8006
                                           mcp-jira:8100
                                           mcp-mindwtr:8787
                                           mcp-infra:8300
                                           mcp-imap:8400
                                           mcp-freebox:8500
```

Le conteneur `claude` ne monte plus `~/.ssh/` ni aucun dossier de tokens OAuth — ces
secrets vivent exclusivement dans les conteneurs `mcp-services` correspondants,
jamais accessibles depuis ici.

## MCP configurés

Tous accessibles via HTTP/SSE réseau, aucune commande locale (`npx`, `ssh`, etc.) :

| Nom dans `mcp.json` | Service `mcp-services` | Type |
|---|---|---|
| `gmail-pro`, `gdrive-pro`, `gcal-pro` | `mcp-google-pro` | sse |
| `gmail-perso`, `gdrive-perso`, `gcal-perso` | `mcp-google-perso` | sse |
| `jira` | `mcp-jira` | http |
| `mindwtr` | `mcp-mindwtr` | sse |
| `infra` | `mcp-infra` | sse |
| `imap` | `mcp-imap` | http |
| `freebox` | `mcp-freebox` | http |

Le type (`sse` vs `http`) dépend de l'implémentation côté `mcp-services` : `sse` pour
les MCP tiers pontés via `mcp-proxy` (stdio→réseau), `http` (streamable-http natif)
pour les serveurs MCP Python écrits directement pour ce repo (Jira, IMAP, Freebox).

## Prérequis avant de lancer claude-sandbox

`mcp-services` doit déjà tourner (au moins les services listés ci-dessus dont Claude
a besoin) — `claude-sandbox` ne les démarre pas, il les consomme. Voir
`mcp-services/README.md` pour le lancement (`scripts/launch.sh`).

## Modifier la configuration MCP

Éditer `config/mcp.json` dans ce repo. Le fichier est monté en ro dans le conteneur —
redémarrer le conteneur `claude` pour que la config soit rechargée.

## Note de sécurité

`config/mcp.json` ne contient que des URLs internes au réseau Docker — aucun secret,
aucune commande, aucun chemin de credentials. Les secrets réels (tokens OAuth,
mots de passe, API keys) vivent exclusivement côté `mcp-services`, injectés au
lancement via `cmdp`, jamais visibles de `claude-sandbox`.
