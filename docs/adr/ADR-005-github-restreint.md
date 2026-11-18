# ADR-005 — Accès GitHub restreint pour le Claude isolé (variante infra)

- Statut : proposée (2026-11-18, issue #2)
- Contexte : ADR-004 (variante infra), « À trancher » : `github` inclus **sous conditions**

## Besoin

Le Claude isolé doit pouvoir lire les dépôts, créer des branches, committer, ouvrir des **PR en brouillon** et
commenter. Il ne doit **ni merger**, ni supprimer de branche protégée ou de dépôt, ni modifier les réglages, secrets
ou protections d'un dépôt.

## Constats (documentation officielle, lue le 2026-11-18)

1. **Le jeton ne peut pas interdire le merge.** D'après la page *Permissions required for fine-grained personal
   access tokens* (docs.github.com, section *Contents*), `PUT /repos/{owner}/{repo}/pulls/{pull_number}/merge`
   demande **Contents: write**, comme `POST /repos/{owner}/{repo}/git/refs` (création de branche) et les commits.
   Un jeton qui peut committer peut donc aussi merger.
2. **Le jeton peut interdire le reste.** La modification des réglages, la suppression d'un dépôt, les protections
   et les règles relèvent de la permission *Administration* ; les secrets relèvent de *Secrets* ; les workflows de
   *Workflows*. Il suffit de ne pas accorder ces permissions.
3. **Le serveur MCP officiel peut retirer des outils.** C'est la documentation de `github-mcp-server`
   (`README.md`, `docs/server-configuration.md`) :
   - `GITHUB_TOOLSETS` donne une liste blanche de jeux d'outils ;
   - `GITHUB_EXCLUDE_TOOLS` retire des outils précis, et ce retrait « l'emporte » toujours, même sur un outil
     ajouté par `--tools` ;
   - `merge_pull_request` appartient au jeu `pull_requests`, et `delete_repository` au jeu `repos`.
   En mode HTTP distant, les mêmes réglages existent sous forme d'en-têtes (`X-MCP-Tools`,
   `X-MCP-Exclude-Tools`…), mais ils sont **posés par le client**.
4. **Le client n'est pas une barrière.** Le Claude isolé a Bash et curl, et il joint directement les services de
   `mcp-sandbox-net`. Une restriction déclarée seulement dans `config/mcp-infra.json` (en-têtes) ou dans
   Claude Code pourrait donc être contournée par une requête faite à la main.
5. **Protection de branche et rulesets** : d'après la page *About rulesets*, ils ne sont proposés qu'aux
   offres Team et Enterprise. L'issue #2 rappelle par ailleurs qu'ils sont indisponibles sur les dépôts privés
   en GitHub Free. Ils ne peuvent donc pas être la barrière principale ; c'est à vérifier dépôt par dépôt
   (dépôts publics, offre du compte ou de l'organisation).

## Décision

1. **Une instance MCP GitHub dédiée** au Claude isolé : `mcp-github-restreint` dans `docker/compose.infra.yml`.
   Ce n'est jamais le `mcp-github` de mcp-services, qui porte le jeton classique du poste et peut merger. Le jeton
   reste dans ce conteneur ; `claude-infra` ne le reçoit pas.
2. **Le filtrage se fait côté serveur**, par variables d'environnement du conteneur que le Claude isolé ne peut
   pas modifier :
   - `GITHUB_TOOLSETS=context,repos,pull_requests,issues` ;
   - `GITHUB_EXCLUDE_TOOLS=merge_pull_request,delete_repository,create_repository,fork_repository,delete_file`.
3. **Le jeton à grain fin est dédié et limité aux dépôts utiles.** Il porte uniquement :
   - *Contents* : lecture et écriture ;
   - *Pull requests* : lecture et écriture ;
   - *Issues* : lecture et écriture ;
   - *Metadata* : lecture (obligatoire).
   Il n'a **ni Administration, ni Secrets, ni Workflows, ni Actions, ni Environments**. C'est une défense en
   profondeur : si l'outil de merge réapparaissait, le jeton bloquerait quand même les réglages et les secrets,
   mais pas le merge.
4. **Protection de `main`** par une règle « pull request obligatoire », là où l'offre le permet. C'est une
   couche en plus, pas la barrière.
5. **PR en brouillon** : le paramètre `draft` de `create_pull_request` ne peut pas être imposé par le serveur.
   La consigne est dans `config/CLAUDE-infra.md` ; une PR non brouillon reste sans effet tant qu'elle n'est pas
   mergée.
6. **Vérification avant usage** : `scripts/test-github-restreint.sh <dépôt> <PR jetable>`. Il contrôle
   l'absence de l'outil de merge, puis tente un merge, y compris en réclamant l'outil par en-tête, et vérifie
   que la PR reste ouverte.

## Risques résiduels

- **Commit direct sur `main`** : `create_or_update_file` et `push_files` acceptent n'importe quelle branche, et
  *Contents: write* le permet. Seules une protection de branche ou un ruleset l'empêchent, sinon la consigne et
  la relecture. À surveiller.
- **En-têtes et filtre serveur** : rien dans la documentation ne dit si un en-tête `X-MCP-Tools` peut rajouter
  un outil exclu par `GITHUB_EXCLUDE_TOOLS` sur un serveur local en mode HTTP. La documentation donne
  l'exclusion comme prioritaire ; l'étape 3 du test le vérifie en conditions réelles.
- **Image `:latest`** : une nouvelle version pourrait renommer des outils (le jeu `pull_requests` a déjà été
  regroupé : `pull_request_read`). Relancer le test après chaque mise à jour de l'image ; épingler un digest
  une fois le test passé.

## Procédure (opérateur) — création et dépôt du jeton

1. GitHub → *Settings* → *Developer settings* → *Personal access tokens* → **Fine-grained tokens** →
   *Generate new token*.
2. Nom : `claude-sandbox-infra` ; expiration : 90 jours au plus. Propriétaire de la ressource : le compte ou
   l'organisation des dépôts visés. Si l'organisation exige une approbation des jetons, la demander.
3. *Repository access* : **Only select repositories**, avec la liste des dépôts utiles à la variante.
4. *Repository permissions* : *Contents* = Read and write, *Pull requests* = Read and write, *Issues* = Read and
   write ; *Metadata* = Read-only (imposé). **Tout le reste à « No access »**, en particulier Administration,
   Secrets, Workflows, Actions, Environments. Aucune permission de compte.
5. Déposer le jeton sur l'hôte, sans l'afficher :
   `install -m 600 /dev/null ~/.config/claude-sandbox/github-token-infra`, puis coller le jeton dans ce fichier
   avec un éditeur. Autre chemin possible : variable `CLAUDE_SANDBOX_GITHUB_TOKEN_FILE`.
6. `./scripts/run-infra.sh` lance alors `mcp-github-restreint` (profil compose `github`). Sans fichier, la session
   démarre sans MCP github.
7. Ouvrir une PR jetable sur un dépôt de la liste, puis lancer
   `./scripts/test-github-restreint.sh <propriétaire/dépôt> <numéro>` : le résultat doit être `RÉSULTAT : OK`.
8. À l'expiration ou en cas de doute : révoquer le jeton sur GitHub et supprimer le fichier.
