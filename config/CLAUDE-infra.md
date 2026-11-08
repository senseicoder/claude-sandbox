# CLAUDE.md — profil « infra » (claude-sandbox, variante isolée)

Modèle copié dans `~/.claude-infra/CLAUDE.md` au premier lancement par `scripts/run-infra.sh`
(jamais écrasé ensuite : l'opérateur l'adapte). Aucune donnée d'infrastructure ici.

## Où je tourne

- Conteneur isolé : système de fichiers en lecture seule, aucun accès réseau direct aux
  serveurs, sortie Internet limitée aux domaines Anthropic.
- Je n'ai **ni SSH, ni Ansible, ni inventaire, ni clé Git, ni jeton GitHub** : ce n'est pas
  un oubli à contourner, c'est la conception (ADR-004 du dépôt claude-sandbox).
- Seul dossier d'échange avec l'opérateur : `/exchange`.

## Outils

- **Serveurs : uniquement le MCP `mcp-infra`** (catalogue fermé de rôles de collecte relus).
  1. `list_roles` / `describe_role` avant toute collecte ; `list_hosts` pour le périmètre.
  2. `get_facts` pour l'état d'un hôte (`frais: true` si le cache est vide ou ancien).
  3. `run_roles` pour une collecte ; relire un lancement long par `get_run`.
  4. Un refus de paramètre est voulu : corriger la demande, jamais chercher à le contourner.
- **Si aucun rôle ne couvre le besoin** ou si l'hôte est hors périmètre : le dire, puis
  écrire dans `/exchange` un script de collecte que **l'opérateur** relira et lancera lui-même,
  avec en tête `# MCP : non couvert — <raison>`. Jamais d'action modifiante proposée comme
  collecte.
- Messagerie, documents, agenda pro et tickets : MCP `gmail-pro`, `gdrive-pro`, `gcal-pro`,
  `jira`. Aucun envoi de mail, commentaire ou changement de ticket sans validation explicite
  de l'opérateur.

## Règles

- Rapporter ce qui a été observé (sortie d'un rôle, `run_id`), pas une conclusion déduite.
- Une absence de résultat n'est pas une preuve d'absence : dire où j'ai cherché.
- Ne jamais afficher de secret relevé dans une sortie, même partiellement.
