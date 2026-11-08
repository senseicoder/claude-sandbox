# ADR-004 — Variante « infra » : Claude isolé, abonnement, MCP pro, aucun accès direct aux serveurs

- **Statut** : Proposé
- **Date** : 2026-11-08

## Contexte

Le serveur MCP `mcp-infra` (dépôt `mcp-infra-readonly`, v2) n'exécute que des rôles de
collecte relus. Mais sur le poste de l'opérateur, l'agent qui l'appelle dispose aussi de
l'agent SSH, de l'inventaire, d'un client Ansible, d'une clé Git et d'un jeton GitHub : il
pourrait atteindre les serveurs **à côté** du MCP. C'est le risque « l'agent garde d'autres
accès sur le poste » de `mcp-infra-readonly/SECURITY.md`.

La variante générale de ce dépôt (`compose.yml`) ne règle pas ce point pour ce besoin : elle
utilise une clé API (écartée par l'opérateur au profit de l'abonnement), monte `~/.claude`,
tout `~/www` et le vault en écriture, et tous les MCP.

Précisions de l'opérateur (2026-11-08) : le Claude isolé a besoin de `mcp-infra` et de
Google pro ; Google perso et IMAP ne sont pas nécessaires ; les autres MCP restent à trancher.

## Décision

Une seconde variante, `docker/compose.infra.yml`, lancée par `scripts/run-infra.sh`, sans
modifier la variante générale :

1. **Même image, même durcissement** : système de fichiers en lecture seule, `cap_drop: ALL`,
   `no-new-privileges`, uid 1000, réseau `mcp-sandbox-net` seul, sortie Internet par
   `egress-proxy` uniquement. L'image ne contient ni `ssh`, ni `ansible`, ni identifiant.
2. **Aucun accès direct aux serveurs ni aux secrets du poste** : pas d'agent SSH, pas
   d'inventaire, pas de clé Git, pas de jeton GitHub, pas de `~/www` ni de vault par défaut.
   Les serveurs ne sont joignables que par `mcp-infra`.
3. **Authentification par abonnement**, jamais de clé API (le script refuse
   `ANTHROPIC_API_KEY`) : profil dédié `~/.claude-infra`, connecté une fois sur l'hôte avec
   `CLAUDE_CONFIG_DIR=~/.claude-infra claude` puis `/login`. Les identifiants vont dans
   `$CLAUDE_CONFIG_DIR/.credentials.json` (mode 600) — documentation Claude Code, page
   `iam`, « Credential management ». Le profil est monté en écriture : sessions et
   renouvellement du jeton. Jamais `~/.claude`.
4. **Proxy de sortie** : ajout de `claude.ai`, `claude.com`, `platform.claude.com` à
   `api.anthropic.com` — requis pour la connexion claude.ai et l'échange/renouvellement du
   jeton OAuth (documentation Claude Code, page `network-config`, « Network access
   requirements », lue le 2026-11-08). Les connecteurs MCP de claude.ai sont désactivés
   (`ENABLE_CLAUDEAI_MCP_SERVERS=false`) : ils passeraient par un domaine non autorisé.
5. **MCP** : `config/mcp-infra.json`, chargé par `--mcp-config` + `--strict-mcp-config` (aucun
   autre MCP, même déclaré dans le profil). Contenu :

   | MCP | Choix | Raison |
   |---|---|---|
   | `mcp-infra` | inclus | raison d'être de la variante (en `http` sur `/mcp`, comme sur le poste) |
   | `gmail-pro`, `gdrive-pro`, `gcal-pro` | inclus | demandé par l'opérateur |
   | `jira` | inclus | tickets d'exploitation, usage pro évident — à confirmer |
   | `gmail-perso`, `gdrive-perso`, `gcal-perso` | exclus | décision de l'opérateur |
   | `imap` | exclus | décision de l'opérateur |
   | `mindwtr` | exclu, à trancher | gestion de tâches personnelle |
   | `freebox`, `homeassistant`, `tuya` | exclus, à trancher | réseau et domotique de la maison |
   | `github` | exclu, à trancher | absent de `mcp-sandbox-net` dans mcp-services ; et l'accès GitHub de cette variante doit passer par des tokens à grain fin dédiés, pas par le jeton du poste |

6. **CLAUDE.md du profil** : modèle `config/CLAUDE-infra.md` (serveurs par `mcp-infra`
   seulement, catalogue d'abord, script de collecte remis à l'opérateur dans `/exchange` si
   rien ne couvre le besoin), copié une seule fois dans le profil.
7. **Dossier d'échange** propre : `~/Work/cnt/claude-sandbox-infra` → `/exchange`.

## Conséquences

- Le Claude isolé ne peut modifier aucun dépôt : il produit dans `/exchange` (scripts,
  analyses, correctifs) et l'opérateur reprend. Un montage en lecture seule de dépôts est
  proposé en commentaire dans le compose, à décider.
- Pas de mémoire ni de wiki partagés avec le profil principal : volontaire (pas de mélange
  pro/perso), mais ce Claude repart d'un contexte plus pauvre.
- Le proxy élargi profite aussi à la variante générale (même `squid.conf`) ; il reste limité
  à des domaines Anthropic exacts, en CONNECT 443.

## Non vérifié à la rédaction

Conformément au `CLAUDE.md` du dépôt, **Docker n'a pas été lancé** : ni build, ni démarrage.
Restent à vérifier au premier test réel : la connexion par abonnement à travers le proxy
(liste de domaines suffisante ?), la joignabilité de chaque MCP sur `mcp-sandbox-net`,
l'impossibilité d'un `ssh`/`ansible` depuis le conteneur, la lecture du CLAUDE.md du profil.

## Alternatives rejetées

- **Étendre la variante générale** : elle monte `~/www`, le vault et `~/.claude` en écriture et
  tous les MCP — l'isolation recherchée y disparaît.
- **Clé API** : écartée par l'opérateur (abonnement uniquement).
- **Monter `~/.claude`** : mélangerait la mémoire, les réglages et les permissions du profil
  principal avec ceux du Claude isolé.
