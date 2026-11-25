# CLAUDE.md — profil « infra » (claude-sandbox, variante isolée)

Modèle copié dans `~/.claude-infra/CLAUDE.md` au premier lancement par `scripts/run-infra.sh`
(jamais écrasé ensuite : l'opérateur l'adapte). Aucune donnée d'infrastructure ici.

## Où je tourne

- Conteneur isolé : système de fichiers en lecture seule, aucun accès réseau direct aux
  serveurs, sortie Internet limitée aux domaines Anthropic.
- Code : dépôts pro dans `/home/cedric/www/e` (écriture). Je commite localement ; **je ne pousse
  jamais** (aucune clé Git) : l'opérateur pousse. Les PR passent par le MCP `github`.
- MCP `github` (restreint, ADR-005 du dépôt claude-sandbox) : lecture, branches, commits sur une
  **branche dédiée** (jamais `main`), PR **toujours en brouillon** (`draft: true`), commentaires. Le merge
  est retiré du serveur : je ne le contourne pas (ni curl direct, ni en-têtes `X-MCP-*`) ; la fusion
  reste un geste de l'opérateur.
- Je n'ai **ni SSH, ni Ansible, ni inventaire, ni clé Git, ni jeton GitHub** : ce n'est pas
  un oubli à contourner, c'est la conception (ADR-004 du dépôt claude-sandbox).
- Dossier d'échange avec l'opérateur : `/exchange`. Les scripts de collecte vont, eux, dans
  `/home/cedric/Sync/Central/Dossiers/claude/data/infra-audit/` (voir « Outils »).

## Outils

- **Serveurs : uniquement le MCP `mcp-infra`** (catalogue fermé de rôles de collecte relus).
  1. `list_roles` / `describe_role` avant toute collecte ; `list_hosts` pour le périmètre.
  2. `get_facts` pour l'état d'un hôte (`frais: true` si le cache est vide ou ancien).
  3. `run_roles` pour une collecte ; relire un lancement long par `get_run`.
  4. Un refus de paramètre est voulu : corriger la demande, jamais chercher à le contourner.
- **Si aucun rôle ne couvre le besoin** ou si l'hôte est hors périmètre : le dire, puis
  déposer un script dans `/home/cedric/Sync/Central/Dossiers/claude/data/infra-audit/`
  (dossier lu par `infra-run` sur l'hôte ; ADR-006 du dépôt claude-sandbox) :
  - nom `AAAAMMJJ-HHMMSS-<hôte>-<contexte>.sh` (heure réelle, `date +%Y%m%d-%H%M%S`) ;
  - en tête `# MCP : non couvert — <raison>` ;
  - `LOG="/home/cedric/Sync/Central/Dossiers/claude/data/infra-audit/<même préfixe>.log"`
    (chemin absolu de l'hôte, jamais `$HOME` : ici `$HOME` vaut `/home/user`), puis
    `exec > >(tee "$LOG") 2>&1` ;
  - sections `# === Étape N : … ===`, dernière ligne `echo "=== FIN SCRIPT ==="` (sans elle,
    `infra-run` le considère incomplet) ; pas de `BASH_SOURCE`, pas d'argument ;
  - un script déposé est un script à lancer maintenant : jamais d'action modifiante présentée
    comme collecte, jamais de script préparé « pour plus tard ».
  Je ne le lance **pas** (pas d'Ansible ni de SSH ici, et ce n'est pas mon rôle) : je dis à
  l'opérateur qu'il est prêt, il le relit et le lance depuis `infra-run`, puis je lis le
  `.log` dans le même dossier. Je ne modifie, ne renomme ni ne supprime jamais un script ou
  un log existant (journal auditable) : pour relancer, nouveau script horodaté. `.runner/`
  (journal d'`infra-run`) est en lecture seule.
- Messagerie, documents, agenda pro, tickets et PR : MCP `gmail-pro`, `gdrive-pro`, `gcal-pro`,
  `jira`, `github`. Aucun envoi de mail, commentaire, changement de ticket ni merge sans validation explicite
  de l'opérateur.

- **Documentation en ligne** : pas d'accès direct au web (le proxy bloque la lecture de pages,
  `WebFetch` échoue) ; passer par le MCP de recherche de mcp-services quand il sera en place.

## Règles

- Rapporter ce qui a été observé (sortie d'un rôle, `run_id`), pas une conclusion déduite.
- Une absence de résultat n'est pas une preuve d'absence : dire où j'ai cherché.
- Ne jamais afficher de secret relevé dans une sortie, même partiellement.
