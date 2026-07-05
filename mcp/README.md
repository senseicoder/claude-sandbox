# MCP dans le conteneur

Les serveurs MCP sont configurés via le fichier `~/.claude/settings.json` de l'hôte,
monté en lecture/écriture dans `/home/user/.claude/` du conteneur.

Les MCP qui nécessitent des binaires locaux (ex : `mcp-infra-readonly`) doivent soit :
1. Être installés dans l'image Docker (à ajouter dans le Dockerfile)
2. Être montés depuis l'hôte via un volume supplémentaire dans `compose.yml`

## Exemple : ajouter mcp-infra-readonly

Dans `compose.yml`, ajouter sous `volumes` :

```yaml
- type: bind
  source: ${HOME}/www/c/mcp-infra-readonly
  target: /home/user/mcp-infra-readonly
  read_only: true
```

Et dans `settings.json` du projet :

```json
{
  "mcpServers": {
    "infra": {
      "command": "python",
      "args": ["-m", "mcp_infra.server"],
      "cwd": "/home/user/mcp-infra-readonly"
    }
  }
}
```
