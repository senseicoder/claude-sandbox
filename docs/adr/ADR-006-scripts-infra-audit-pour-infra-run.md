# ADR-006 — Variante infra : scripts de collecte déposés dans infra-audit/ pour infra-run

- **Statut** : Proposé
- **Date** : 2026-11-18
- **Issue** : #3

## Contexte

Quand aucun rôle de `mcp-infra` ne couvre un besoin, l'opérateur applique le pattern
« script+log » : un script `AAAAMMJJ-HHMMSS-<hôte>-<contexte>.sh` est déposé dans
`~/Sync/Central/Dossiers/claude/data/infra-audit/`, l'opérateur le relit et le lance avec
`infra-run` (lanceur interactif de l'hôte : fiche de risques calculée sur le contenu réel,
validation, exécution d'une copie figée), puis l'agent lit le `.log` produit à côté.

ADR-004 faisait remettre ce script dans `/exchange` : l'opérateur devait le recopier à la
main dans `infra-audit/`, et le log ne revenait pas au Claude isolé.

Constaté dans `infra-run` (lecture du code de l'hôte, 2026-11-18) :
- il prend tous les `*.sh` du dossier, sans contrôle de propriétaire ni de bit d'exécution
  (exécution par `bash -c '. <copie figée>'`) ;
- un script sans la ligne `=== FIN SCRIPT ===` est classé « incomplet » et n'est pas proposé ;
- son état (journal par poste, statuts `refuse`, `demarre`…) est dans `infra-audit/.runner/`.

## Décision

1. `~/Sync/Central/Dossiers/claude/data/infra-audit` est monté **en écriture** dans le
   conteneur, au **même chemin absolu** que sur l'hôte (ADR-003), et rien d'autre du poste
   (en plus de `~/www/e`, du profil et de `/exchange`, déjà décidés).
2. `infra-audit/.runner` est monté **en lecture seule** par-dessus : le Claude isolé peut lire
   le journal, mais ni falsifier un statut (`refuse` d'un script, faux `demarre`) ni effacer
   une trace d'exécution.
3. Le conteneur tourne en uid 1000, celui de l'utilisateur de l'hôte : les fichiers créés lui
   appartiennent et `infra-run` les traite comme les siens.
4. **Le lancement reste humain** : `infra-run` tourne sur l'hôte. Le conteneur n'a ni
   `ansible`, ni `ssh`, ni inventaire, ni route vers les serveurs : exécuter le script dans le
   conteneur n'atteint rien. Un montage `noexec` n'apporterait rien : `bash script.sh` lit le
   fichier sans l'exécuter et passe outre.
5. Le modèle `config/CLAUDE-infra.md` décrit la convention : nom horodaté, en-tête
   `# MCP : non couvert — <raison>`, `LOG` en chemin absolu de l'hôte (dans le conteneur,
   `$HOME` vaut `/home/user`), `exec > >(tee "$LOG") 2>&1`, `=== FIN SCRIPT ===`, pas de
   `BASH_SOURCE` ni d'argument (copie figée), jamais de modification d'un script ou d'un log
   existant.
6. `scripts/run-infra.sh` crée `infra-audit/.runner` s'il manque (un bind sans source échoue).

## Conséquences

- Le Claude isolé dépose ses scripts là où `infra-run` les attend et lit lui-même les logs :
  plus de recopie par l'opérateur.
- **Risque accepté** : tout le reste du dossier est en écriture — le Claude isolé pourrait
  modifier un ancien script ou un ancien log, ce qui affaiblit la valeur de journal auditable
  du dossier. Atténuations : règle explicite dans le CLAUDE.md du profil ; `infra-run`
  recalcule la fiche de risques et l'empreinte sur le contenu réel à chaque proposition, donc
  un script modifié est réaffiché, jamais exécuté sous l'ancienne validation ; `.runner/` est
  intouchable. Si ce risque devient inacceptable : monter un sous-dossier de dépôt dédié et
  faire lire ce sous-dossier par `infra-run` (modification d'`infra-run`, hors de ce dépôt).
- Le Claude isolé lit tous les logs du dossier, y compris ceux d'autres sessions : ce sont
  des données de production, déjà accessibles au profil principal — voulu par l'issue.
- Le dossier est synchronisé par Syncthing : un script déposé depuis le conteneur apparaît
  aussi sur les autres postes, comme un script déposé par le profil principal.
- **Profil existant** : `run-infra.sh` ne copie le modèle de CLAUDE.md qu'une fois. Un
  `~/.claude-infra/CLAUDE.md` déjà créé doit être mis à jour à la main depuis
  `config/CLAUDE-infra.md` (aucun profil n'existait sur le poste de rédaction le 2026-11-18).

## Non vérifié à la rédaction

Conformément au `CLAUDE.md` du dépôt, **Docker n'a pas été lancé**. À vérifier au premier
test réel, avec `scripts/test-infra-audit.sh` : écriture et propriétaire, refus d'écriture
dans `.runner/` (montage imbriqué en lecture seule), refus ailleurs, lecture d'un log,
absence d'`ansible`/`ssh`. Puis un essai complet : script déposé depuis le conteneur, proposé
par `infra-run`, lancé, log relu dans le conteneur.

## Alternatives rejetées

- **Rester sur `/exchange`** : recopie manuelle, le log ne revient pas.
- **Lancer `infra-run` dans le conteneur** : il exécuterait Ansible depuis le conteneur, donc
  avec agent SSH et inventaire — exactement ce qu'ADR-004 retire.
- **Monter seulement un sous-dossier de dépôt** : plus étanche, mais `infra-run` ne lit que la
  racine d'`infra-audit/` ; demande une évolution d'`infra-run` (piste ci-dessus).
