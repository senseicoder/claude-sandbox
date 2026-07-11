# Analyse de sécurité — claude-sandbox

## Modèle de menace

L'attaquant est une instance Claude Code compromise : injection de prompt, MCP malveillant,
outil détourné, ou comportement inattendu du modèle. L'objectif du sandbox est de limiter
ce qu'une telle instance peut faire sur le système hôte.

---

## Risques couverts

### ✅ Écriture arbitraire sur le disque hôte

**Mécanisme** : `read_only: true` dans compose.yml + seuls les volumes explicitement montés sont accessibles en écriture.

**Ce que ça bloque** : Claude ne peut pas créer de fichiers dans `/etc`, `/usr`, `/bin`, ni dans les répertoires système du conteneur. Une tentative d'écriture hors volume retourne une erreur immédiate.

---

### ✅ Escalade de privilèges via capabilities Linux

**Mécanisme** : `cap_drop: ALL` — toutes les capabilities Linux sont supprimées dès le démarrage du conteneur.

**Ce que ça bloque** : impossibilité de binder un port < 1024, de monter un système de fichiers, de modifier les attributs d'un autre processus, d'utiliser `ptrace`, de manipuler le réseau (`CAP_NET_ADMIN`), etc.

**Capabilities supprimées notables** : `CAP_NET_BIND_SERVICE`, `CAP_NET_ADMIN`, `CAP_SYS_ADMIN`, `CAP_SYS_PTRACE`, `CAP_CHOWN`, `CAP_SETUID`, `CAP_SETGID`, `CAP_DAC_OVERRIDE`.

---

### ✅ Escalade de privilèges via setuid/setgid

**Mécanisme** : `no-new-privileges: true` — un processus ne peut pas acquérir plus de droits que ceux dont il dispose au démarrage, même via un binaire setuid.

**Ce que ça bloque** : `sudo`, `su`, et tout binaire setuid du conteneur sont neutralisés.

---

### ✅ Exécution en root dans le conteneur

**Mécanisme** : `user: "1000:1000"` — le processus tourne en utilisateur non privilégié dans et hors du conteneur (uid 1000 mappé sur uid 1000 de l'hôte).

**Ce que ça bloque** : même en cas d'évasion de conteneur, le processus n'a que les droits de l'utilisateur cedric sur l'hôte — pas de root.

---

### ✅ Pollution des répertoires système du conteneur

**Mécanisme** : combinaison `read_only` + tmpfs sur `/tmp`, `/run`.

**Ce que ça bloque** : les fichiers temporaires créés par Claude Code (caches, sockets) n'existent qu'en mémoire et disparaissent à l'arrêt du conteneur.

---

### ✅ Exfiltration de données via le réseau (résolu 2026-07-11)

**Mécanisme** : réseau `mcp-sandbox-net` (`internal: true`) — aucune route vers Internet. Le conteneur `claude` ne rejoint que ce réseau, rien d'autre. Voir `docs/adr/ADR-001-isolation-reseau-mcp-net.md`.

**Ce que ça bloque** : toute requête HTTP/HTTPS vers un serveur tiers, y compris vers le poste hôte lui-même (`internal: true` ne route que vers les autres conteneurs du même réseau Docker).

**Exception documentée** : `api.anthropic.com`, seule sortie nécessaire à Claude Code lui-même — via `egress-proxy` (squid), dual-homed (`mcp-sandbox-net` + `egress-net`), ACL stricte par domaine. Aucun autre domaine autorisé.

---

### ✅ ~/.ssh — clés SSH exposées (résolu 2026-07-11)

**Ancien mécanisme** : `~/.ssh` était monté en lecture seule pour que `mcp-infra-readonly` (alors exécuté ici) puisse s'en servir.

**Résolution** : `mcp-infra-readonly` est désormais un service réseau dans `mcp-services`, avec la clé SSH montée dans **son propre** conteneur, jamais dans `claude-sandbox`. Ce repo ne monte plus `~/.ssh` du tout — le risque est fermé par suppression, pas par mitigation partielle. Voir `docs/adr/ADR-002-migration-mcp-services.md`.

---

### ✅ Persistence entre sessions

**Mécanisme** : le conteneur est éphémère (`restart: "no"`, `--rm` dans run.sh). Seuls les volumes montés persistent.

**Ce que ça bloque** : un backdoor écrit dans le conteneur (hors volumes) disparaît à l'arrêt.

---

## Risques restants

### ⚠️ Lecture de l'intégralité de ~/.claude/ et du workspace

**Description** : les volumes montés en rw sont pleinement lisibles par Claude. Cela inclut `~/.claude/` (sessions passées, mémoires, tokens) et tout le dossier de code monté.

**Impact** : Claude peut lire des secrets stockés dans les sessions, des tokens dans les fichiers de config, du code source sensible.

**Mitigation possible** : monter uniquement les sous-dossiers strictement nécessaires plutôt que `~/.claude/` entier. Exemple : monter uniquement `~/.claude/projects/<projet-en-cours>/` en rw et `~/.claude/settings.json` en ro.

---

### ⚠️ Écriture dans les volumes montés

**Description** : les volumes `~/.claude/`, `/workspace` et `/exchange` sont montés en écriture. Claude peut modifier, supprimer ou corrompre des fichiers dans ces dossiers.

**Impact** : corruption de la config Claude, suppression de code, injection de fichiers malveillants dans le workspace.

**Mitigation possible** : sauvegardes régulières des volumes critiques. Pour `~/.claude/`, envisager un snapshot avant chaque session.

---

### ⚠️ Évasion de conteneur via vulnérabilité Docker/kernel

**Description** : une vulnérabilité dans le runtime Docker ou le kernel Linux peut permettre une sortie du namespace de conteneur malgré les protections.

**Impact** : accès complet à l'hôte si la vulnérabilité est exploitée.

**Mitigation possible** : maintenir Docker et le kernel à jour. Envisager gVisor (`--runtime=runsc`) pour une isolation kernel plus forte.

---

### ⚠️ Dépendances npm de Claude Code

**Description** : Claude Code et ses dépendances npm sont exécutés dans le conteneur. Une dépendance compromise (supply chain attack) pourrait contenir du code malveillant.

**Impact** : exécution de code arbitraire dans le contexte du conteneur.

**Mitigation possible** : verrouiller les versions npm dans le Dockerfile (`npm install @anthropic-ai/claude-code@<version-exacte>`), vérifier les hash des packages.

---

### ⚠️ MCP tiers avec accès réseau

**Description** : les MCP configurés dans `~/.claude/` peuvent eux-mêmes faire des appels réseau, accéder à des APIs, ou avoir des vulnérabilités propres.

**Impact** : contournement des restrictions du conteneur via un MCP mal sécurisé.

**Mitigation possible** : n'autoriser que des MCP connus et audités. Idéalement, monter la config MCP en lecture seule.

---

### ℹ️ MindWTR — résolu différemment (2026-07-11)

**Ancien problème** : le tunnel SSH vers mnementh7 exposait l'API MindWTR sur `localhost:3456` de l'hôte, invisible depuis le réseau bridge Docker.

**Résolution** : `mcp-mindwtr` est désormais un service réseau dans `mcp-services` (dual-homed `mcp-net`/`mcp-sandbox-net`), joignable via `http://mcp-mindwtr:8787/sse` — plus de dépendance à un `localhost` de l'hôte. Voir `config/mcp.json`.

---

## Tableau récapitulatif

| Risque | Couvert | Résiduel | Priorité |
|---|---|---|---|
| Écriture système hôte hors volumes | ✅ read_only | — | — |
| Escalade privilege Linux | ✅ cap_drop ALL | — | — |
| Escalade via setuid | ✅ no-new-privileges | — | — |
| Exécution en root | ✅ user 1000 | — | — |
| Persistence conteneur | ✅ éphémère | — | — |
| Exfiltration réseau | ✅ mcp-sandbox-net internal + egress-proxy | — | — |
| ~/.ssh monté — clés SSH exposées | ✅ supprimé (mcp-infra-readonly isolé ailleurs) | — | — |
| Lecture volumes sensibles | ⚠️ granularité grossière | ~/.claude/, ~/www, vault Obsidian entiers exposés | Moyenne |
| Écriture dans volumes | ⚠️ intentionnel | possible corruption sur www/vault entiers, pas un seul projet | Moyenne |
| Évasion kernel/Docker | ⚠️ atténué par user 1000 | CVE non patchées | Basse |
| Supply chain npm | ⚠️ versions non verrouillées | dépendances non auditées | Moyenne |
| MCP tiers malveillant | ⚠️ non filtré | accès réseau MCP (mais chaque MCP tourne isolé côté mcp-services) | Haute |
| MindWTR | ✅ résolu — service réseau mcp-services | — | — |
