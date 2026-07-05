# MCP dans le conteneur

Les MCP sont configurés via `config/mcp.json` à la racine du repo, monté en lecture seule comme `/home/user/.claude.json` dans le conteneur. Claude Code lit ce fichier au démarrage comme sa configuration MCP globale.

## Architecture

```
Hôte                                   Conteneur
─────────────────────────              ─────────────────────────────────
config/mcp.json (ce repo) ──── ro ──▶  /home/user/.claude.json

~/.config/google-drive-mcp/  ─ rw ──▶  /home/user/.config/google-drive-mcp/
~/.config/google-calendar-mcp/ rw ──▶  /home/user/.config/google-calendar-mcp/
~/.ssh/                       ─ ro ──▶  /home/user/.ssh/
```

## MCP configurés

### Gmail (`@gongrzhe/server-gmail-autoauth-mcp`)

MCP npm installé nativement dans l'image. Authentification OAuth interactive au premier lancement.

### Google Drive (`@piotr-agier/google-drive-mcp`)

MCP npm installé nativement. Utilise `~/.config/google-drive-mcp/gcp-oauth.keys.json` pour les credentials. Les tokens générés sont persistés dans `~/.config/google-drive-mcp/` (volume rw).

Pour créer le fichier de credentials :
1. Créer un projet GCP avec l'API Drive activée
2. Créer des credentials OAuth2 Desktop app
3. Télécharger le JSON → `~/.config/google-drive-mcp/gcp-oauth.keys.json`

### Google Calendar (`@nspady/google-calendar-mcp`)

MCP npm installé nativement. Partage le fichier `gcp-oauth.keys.json` de GDrive (même projet GCP). Les tokens sont persistés dans `~/.config/google-calendar-mcp/` (volume rw).

### mcp-infra-readonly

Ce MCP n'est pas installé dans l'image. Il est accessible depuis le conteneur via SSH : le repo `mcp-infra-readonly` doit être installé sur le serveur cible, et Claude le lance via SSH en passant par les clés montées depuis `~/.ssh/`.

Configuration dans `config/mcp.json` :
```json
"infra": {
  "command": "ssh",
  "args": ["<serveur>", "python -m mcp_infra.server"],
  "env": {}
}
```

## Premier lancement

Au premier lancement, les MCP Gmail et Google Drive/Calendar demanderont une authentification OAuth interactive. Un lien URL sera affiché dans le terminal — ouvrir dans un navigateur, s'authentifier, puis copier le code de retour. Les tokens sont ensuite sauvegardés dans les volumes rw et réutilisés automatiquement.

## Modifier la configuration MCP

Éditer `config/mcp.json` dans ce repo. Le fichier est monté en ro dans le conteneur — aucun redémarrage du service MCP n'est nécessaire, mais il faut redémarrer le conteneur pour que Claude recharge sa config.

## Note de sécurité

`config/mcp.json` ne contient aucun secret — uniquement des commandes et des chemins de fichiers. Les credentials OAuth réels sont dans `~/.config/google-drive-mcp/` sur l'hôte, hors du repo git.
