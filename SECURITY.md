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

### ✅ Persistence entre sessions

**Mécanisme** : le conteneur est éphémère (`restart: "no"`, `--rm` dans run.sh). Seuls les volumes montés persistent.

**Ce que ça bloque** : un backdoor écrit dans le conteneur (hors volumes) disparaît à l'arrêt.

---

## Risques restants

### ⚠️ Exfiltration de données via le réseau

**Description** : le conteneur a accès au réseau par défaut (bridge Docker). Claude peut faire des requêtes HTTP/HTTPS vers l'extérieur, envoyer des données à un serveur tiers.

**Impact** : exfiltration des secrets présents dans les volumes montés (`~/.claude/`, workspace).

**Mitigation possible** : créer un réseau Docker sans accès internet ou avec un firewall egress strict.
```yaml
# compose.yml — à ajouter
networks:
  default:
    driver: bridge
    internal: true  # pas d'accès internet
```
Attention : Claude Code a besoin d'accès à `api.anthropic.com`. Il faut soit autoriser uniquement ce domaine (via proxy), soit accepter ce risque résiduel.

---

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

### ⚠️ ~/.ssh monté en lecture seule — surface d'attaque élargie

**Description** : le volume `~/.ssh` est monté en ro pour permettre au MCP `mcp-infra-readonly` d'accéder aux serveurs d'infrastructure via SSH. Les clés SSH privées sont donc accessibles dans le conteneur.

**Contexte** : ce montage n'est pas lié aux MCP Gmail/GDrive/Calendar, qui sont désormais installés en natif dans le conteneur et utilisent OAuth (pas SSH). Il est exclusivement nécessaire pour l'accès lecture aux serveurs via `mcp-infra-readonly`.

**Impact** : si Claude Code est compromis, il peut lire les clés SSH et les utiliser pour se connecter à n'importe quel serveur accessible depuis le poste.

**Mitigation possible** : créer une clé SSH dédiée au conteneur sandbox, avec droits restreints sur les seuls serveurs infra (pas d'accès à d'autres machines). Monter uniquement `~/.ssh/config` + la clé dédiée plutôt que `~/.ssh/` entier.

**Todo** : créer `~/.ssh/id_sandbox` et configurer `~/.ssh/config` pour que mcp-infra-readonly utilise cette clé.

---

### ℹ️ MindWTR (localhost:3456) non accessible depuis le conteneur

**Description** : le tunnel SSH vers mnementh7 expose l'API MindWTR sur `localhost:3456` de l'hôte. Le réseau bridge Docker ne voit pas ce localhost.

**Mitigation** : soit utiliser `network_mode: host` (réduit l'isolation réseau), soit créer un service Docker supplémentaire qui proxy le port. Pour l'instant, MindWTR n'est pas disponible dans la sandbox — les scripts MindWTR (`mw-tasks.sh`, etc.) échoueront silencieusement.

**Todo** : évaluer si `network_mode: host` est acceptable pour les sessions sandbox nécessitant MindWTR.

---

## Tableau récapitulatif

| Risque | Couvert | Résiduel | Priorité |
|---|---|---|---|
| Écriture système hôte hors volumes | ✅ read_only | — | — |
| Escalade privilege Linux | ✅ cap_drop ALL | — | — |
| Escalade via setuid | ✅ no-new-privileges | — | — |
| Exécution en root | ✅ user 1000 | — | — |
| Persistence conteneur | ✅ éphémère | — | — |
| Exfiltration réseau | ⚠️ non restreint | réseau bridge ouvert | Haute |
| Lecture volumes sensibles | ⚠️ granularité grossière | ~/.claude/ entier exposé | Moyenne |
| Écriture dans volumes | ⚠️ intentionnel | possible corruption | Moyenne |
| Évasion kernel/Docker | ⚠️ atténué par user 1000 | CVE non patchées | Basse |
| Supply chain npm | ⚠️ versions non verrouillées | dépendances non auditées | Moyenne |
| MCP tiers malveillant | ⚠️ non filtré | accès réseau MCP | Haute |
| ~/.ssh monté — clés SSH exposées | ⚠️ nécessaire pour mcp-infra-readonly | clé dédiée sandbox à créer | Moyenne |
| MindWTR (localhost:3456) inaccessible | ℹ️ réseau bridge | network_mode: host si besoin | Info |
