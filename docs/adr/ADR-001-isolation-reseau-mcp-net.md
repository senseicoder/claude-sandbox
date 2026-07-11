# ADR-001 — Isolation réseau : uniquement les services MCP, zéro internet, zéro poste local

- **Statut** : Accepté
- **Date** : 2026-07-11

## Contexte

`SECURITY.md` flaguait déjà ce risque comme non couvert : *"le conteneur a accès au
réseau par défaut (bridge Docker). Claude peut faire des requêtes HTTP/HTTPS vers
l'extérieur, envoyer des données à un serveur tiers."* Avec l'ancienne architecture
(MCP Gmail/Drive/Calendar installés en natif dans ce conteneur, `api.anthropic.com`
à joindre), un blocage réseau total n'était pas possible sans casser Claude Code
lui-même.

Depuis, `mcp-services` a pris en charge tous les MCP externes (Gmail, Drive,
Calendar, Jira, IMAP, Freebox, infra) dans des conteneurs réseau dédiés, accessibles
via `mcp-net`. Ce repo (`claude-sandbox`) n'a donc plus besoin d'accès natif à
Internet pour ces services — seulement d'atteindre les conteneurs MCP.

Décision de Cédric (2026-07-11) : `claude-sandbox` ne doit voir **que** les services
MCP, "aucun accès à internet, pas le droit de sortir du réseau, et même pas
d'accéder à un service local sur mon pc."

## Décision

Un réseau Docker dédié, **`mcp-sandbox-net`** (`internal: true`), séparé de
`mcp-net`. `claude-sandbox` rejoint uniquement ce réseau — aucun autre réseau, pas de
réseau par défaut. Chaque service `mcp-services` qui doit être joignable depuis le
sandbox rejoint **les deux réseaux** : `mcp-net` (pour ses propres appels vers
Internet — Google, Atlassian, Infomaniak, Free) et `mcp-sandbox-net` (pour être
joignable par `claude-sandbox`).

`mcp-sandbox-net` est créé côté `mcp-services` (comme `mcp-net`, avec
`external: true` pour que `claude-sandbox` puisse le rejoindre depuis son propre
`docker-compose.yml`).

Comme `mcp-sandbox-net` est `internal: true` :
- pas de route vers Internet depuis ce réseau — la restriction est appliquée par
  Docker lui-même (`iptables`, pas une convention de config)
- pas d'accès au `localhost`/services du poste hôte — `internal: true` ne route que
  vers les autres conteneurs du même réseau Docker

**`api.anthropic.com`** (nécessaire à Claude Code lui-même) : Docker ne permet pas un
réseau "internal, sauf ce domaine" — `internal: true` bloque toute sortie sans
exception possible par domaine. Décision Cédric (2026-07-11) : sortie limitée
strictement aux serveurs Anthropic nécessaires, via un **proxy de sortie dédié**.

`egress-proxy` (squid, ACL par domaine — `dstdomain api.anthropic.com`, tout le reste
refusé) rejoint **deux réseaux** : `mcp-sandbox-net` (pour être joignable par
`claude-sandbox`) et un réseau dédié à sa propre sortie Internet (`egress-net`, non
`internal`, utilisé uniquement par ce proxy — pas par les services MCP). `claude`
(le conteneur Claude Code) reste sur `mcp-sandbox-net` uniquement, configuré avec
`HTTPS_PROXY=http://egress-proxy:3128`.

Si d'autres domaines Anthropic s'avèrent nécessaires au démarrage réel (télémétrie,
etc., non identifiés à l'écriture de cet ADR), l'ACL squid est le point unique à
étendre — pas de nouveau réseau à créer.

## Conséquences

- **Positif** : le risque "Exfiltration de données via le réseau" documenté dans
  `SECURITY.md` est fermé par construction, pas par une règle qu'on espère ne pas
  oublier — et Claude Code garde sa seule sortie strictement nécessaire.
- **Négatif** : toucher `mcp-services/docker-compose.yml` pour ajouter
  `mcp-sandbox-net` à chaque service — surface de changement dans un repo qui
  fonctionne déjà en production légère (Google, Jira testés).
- **Négatif** : composant de plus à maintenir (`egress-proxy`) — mais isolé,
  read-only, cap_drop ALL comme les autres services de ce repo.

## Alternatives considérées

- **Faire rejoindre `mcp-net` directement à `claude-sandbox`** : rejeté — `mcp-net`
  n'est pas `internal`, les services dessus ont besoin d'Internet pour leurs propres
  appels ; le rejoindre directement donnerait aussi Internet à `claude-sandbox`.
- **Firewall/iptables interne au conteneur** : rejeté — demanderait `CAP_NET_ADMIN`,
  contraire au principe `cap_drop: ALL` déjà en place.
