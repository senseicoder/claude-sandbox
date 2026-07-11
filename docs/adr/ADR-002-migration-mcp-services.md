# ADR-002 — Migration vers mcp-services : retrait des MCP natifs et de ~/.ssh

- **Statut** : Accepté
- **Date** : 2026-07-11

## Contexte

Ce repo installait jusqu'ici Gmail, Google Drive et Google Calendar **en natif** dans
le conteneur Claude (`docker/Dockerfile`, `config/mcp.json`), avec les tokens OAuth
montés en volume rw depuis l'hôte. `SECURITY.md` documentait déjà pourquoi c'était un
choix temporaire : ces tokens sont des fichiers lisibles par le processus Claude Code
lui-même — accessibles à Claude, ce qui contredit le principe recherché.

`~/.ssh/` était monté en lecture seule pour que `mcp-infra-readonly` (alors exécuté
côté client, dans ce conteneur) puisse s'en servir. `SECURITY.md` flaguait déjà ce
risque avec un TODO explicite : créer une clé dédiée `id_sandbox`.

Depuis, `mcp-services` (repo séparé) prend en charge tous ces services dans des
conteneurs réseau isolés, secrets jamais accessibles à Claude. `mcp-infra-readonly`
lui-même est désormais intégré à `mcp-services` (voir son `ADR-004`), avec la clé SSH
personnelle de Cédric montée **dans ce conteneur-là**, pas dans `claude-sandbox`.

## Décision

- Retrait de `docker/Dockerfile` : `@gongrzhe/server-gmail-autoauth-mcp`,
  `@piotr-agier/google-drive-mcp`, `@nspady/google-calendar-mcp`.
- Retrait de `docker/compose.yml` : volumes `~/.ssh`, `~/.config/google-drive-mcp`,
  `~/.config/google-calendar-mcp`.
- `config/mcp.json` réécrit pour référencer les services réseau de `mcp-services`
  (Gmail/Drive/Calendar pro et perso, Jira, IMAP, Freebox, infra) via leur nom DNS
  Docker sur `mcp-sandbox-net` (voir `ADR-001`), type `sse` ou `http` selon le
  service — jamais de commande `npx` ni de chemin de credentials.

## Conséquences

- **Positif** : ferme les deux risques documentés dans `SECURITY.md`
  ("Écriture dans les volumes montés" côté tokens OAuth, "`~/.ssh` monté en lecture
  seule — surface d'attaque élargie") sans mitigation partielle — les secrets ne sont
  simplement plus accessibles, pas juste mieux protégés.
- **Positif** : ce conteneur perd toute dépendance à des credentials — il ne connaît
  que des URLs réseau internes (`http://mcp-jira:8100/...`), cohérent avec le
  principe déjà posé dans `mcp-services/docs/architecture.md`.
- **Conséquence directe** : plus d'accès SSH direct depuis ce conteneur (ni aux
  serveurs infra, ni pour du `git push` par SSH) — cohérent avec l'isolation réseau
  totale décidée en `ADR-001` (`git push` vers GitHub ne fonctionnerait de toute
  façon pas sans sortie internet). Les commits restent possibles en local ; le push
  se fait depuis une session hors sandbox.

## Alternatives considérées

- **Garder les MCP Google natifs "en attendant"** : rejeté — `mcp-google-pro`/
  `mcp-google-perso` sont déjà validés de bout en bout dans `mcp-services`, aucune
  raison de garder les deux implémentations en parallèle.
