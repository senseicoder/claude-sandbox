# ADR-003 — Workspace élargi à ~/www entier, dossier d'échange généralisé

- **Statut** : Accepté
- **Date** : 2026-07-11

## Contexte

Le workspace était paramétrable via `WORKSPACE` (défaut `~/www/c`), un projet à la
fois. Le dossier d'échange était fixe : `~/claude-exchange` → `/exchange`.

Décision de Cédric (2026-07-11) :
- Le code doit être **modifiable** par le LLM (écriture, pas juste lecture) — c'était
  déjà le cas (`read_only: false` sur ce volume), confirmé explicitement.
- Workspace : `~/www` **entier** (perso `~/www/c/` et pro `~/www/e/`), pas un seul
  projet à la fois.
- Dossier d'échange : généraliser le chemin en `~/Work/cnt/$nomconteneur` plutôt
  qu'un chemin fixe unique — pattern réutilisable pour d'autres conteneurs futurs, pas
  seulement `claude-sandbox`.
- **Chemins identiques hôte/conteneur** (précisé après coup, même session) : `~/www`
  et le vault Obsidian (`~/Sync/Central/Dossiers/obsidian`) doivent être montés au
  **même chemin absolu** à l'intérieur du conteneur qu'à l'extérieur — pas de
  renommage en `/workspace`. Raison : de nombreux fichiers (`CLAUDE.md`, pages wiki,
  `orga.perso.md`/`orga.claude.md`) contiennent des chemins absolus qui se référencent
  entre eux ou pointent vers des scripts — un renommage casserait ces références dès
  que Claude, à l'intérieur du sandbox, les suit.

## Décision

- `docker/compose.yml` : volume `${HOME}/www` → `/home/cedric/www` (chemin identique
  à l'hôte, pas `/workspace`), `rw`.
- Volume `${HOME}/Sync/Central/Dossiers/obsidian` → `/home/cedric/Sync/Central/Dossiers/obsidian`
  (chemin identique), `rw` — le vault entier (contient `epiconcept/`, wiki, todos).
- `docker/Dockerfile` : crée `/home/cedric/www` et
  `/home/cedric/Sync/Central/Dossiers/obsidian` (et non plus `/workspace`), propriété
  de l'utilisateur non privilégié — l'utilisateur runtime du conteneur reste `user`
  (`/home/user` pour `$HOME`/`.claude`), mais le code et le vault vivent sous
  `/home/cedric/` pour matcher les chemins absolus attendus.
- Dossier d'échange : `${HOME}/Work/cnt/claude-sandbox` → `/exchange`, toujours `rw`
  (celui-ci reste renommé, aucun fichier ne référence son chemin en dur).
  `scripts/run.sh` crée ce dossier s'il n'existe pas.
- Convention documentée dans le `README.md` : tout futur conteneur suit le même
  schéma `~/Work/cnt/<nom-du-conteneur>` pour son dossier d'échange.

## Conséquences

- **Positif** : plus besoin de relancer avec `WORKSPACE=...` pour changer de projet
  en cours de session — tout `~/www` est déjà là.
- **Négatif — surface élargie** : Claude a maintenant accès en écriture à *tous* les
  repos perso et pro à la fois, pas un seul projet isolé. Cohérent avec la demande
  explicite de Cédric, mais à garder en tête : une session sur un projet peut, en
  théorie, toucher un autre projet du même coup de `~/www`.
- **Positif** : convention de nommage `~/Work/cnt/$nom` réutilisable sans y repenser
  pour de futurs conteneurs (pas seulement claude-sandbox).

## Alternatives considérées

- **Garder `WORKSPACE` un projet à la fois** : rejeté par Cédric — la friction de
  relancer pour chaque projet n'en vaut pas la peine face au gain d'avoir tout
  accessible d'emblée.
