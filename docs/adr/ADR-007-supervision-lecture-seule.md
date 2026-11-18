# ADR-007 — Variante infra : outils de supervision et de déploiement en lecture seule

- **Statut** : Proposé
- **Date** : 2026-11-18
- **Issue** : #4

## Contexte

Le Claude isolé de la variante infra (ADR-004) doit lire quatre outils : **Grafana**
(tableaux de bord, requêtes Prometheus/Loki), **Alertmanager** (alertes actives, silences),
**GoAlert** (incidents, escalades), **Semaphore** (historique des tâches). Attendus de
l'issue : lecture seule par défaut, jetons dédiés révocables et journalisés, jamais ceux de
l'opérateur ; l'écriture (silence, acquittement, lancement) est hors périmètre.

Contraintes constatées :
- **Alertmanager n'a pas d'authentification** dans l'installation visée : toute machine qui
  le joint peut lire *et* créer des silences (`POST /api/v2/silences`). Aucun jeton ne peut
  donc garantir la lecture seule : il faut filtrer les méthodes avant l'outil.
- **Grafana** exige, en plus du jeton, un certificat client au niveau du frontal.
- **GoAlert** expose une API GraphQL en `POST` : un filtre de méthode ne distingue pas une
  requête d'une mutation.
- L'issue proposait d'ajouter les domaines au proxy de sortie (`egress-proxy`). Mais le
  proxy fait du `CONNECT` : le Claude isolé tiendrait lui-même le canal TLS, il devrait donc
  détenir les jetons et le certificat, et rien n'empêcherait un `POST` vers Alertmanager.

## Décision

1. **Relais dédié `supervision-ro`** (nginx, `docker/supervision-ro/supervision.conf.template`),
   au lieu d'ouvrir le proxy de sortie. Il est sur `mcp-sandbox-net` (joint par
   `claude-infra`) et sur `egress-net` (sortie vers les outils). `claude-infra` reste sur
   `mcp-sandbox-net` seul : il ne joint les outils **que** par le relais.
2. **Le relais détient les secrets**, pas le Claude isolé : il ajoute l'en-tête
   `Authorization` et présente le certificat client Grafana. Le Claude isolé appelle
   `http://supervision-ro:<port>` sans jeton. Un jeton ne peut donc ni fuiter dans une
   session, ni être réutilisé vers un autre outil.
3. **Filtrage par outil** (tout le reste → 403, sans atteindre l'outil) :

   | Port | Outil | Autorisé | Lecture seule garantie par |
   |---|---|---|---|
   | 8091 | Grafana | `GET /api/…`, `POST /api/ds/query` | relais + rôle Viewer du compte de service |
   | 8092 | Alertmanager | `GET /api/v2/…` | **relais seul** (outil sans auth) |
   | 8093 | GoAlert | `POST /api/graphql` | **politique de la clé API** (champs de lecture seulement) |
   | 8094 | Semaphore | `GET /api/…` | relais + rôle Guest de l'utilisateur dédié |

4. **Journalisation** : une ligne par requête (heure, port, méthode, chemin, code) sur la
   sortie standard du relais (`docker compose … logs supervision-ro`), sans en-tête
   d'authentification. Les outils journalisent en plus l'usage du jeton de leur côté.
5. **Configuration hors dépôt**, fournie par l'opérateur :
   `~/.config/claude-sandbox-infra/supervision.env` (URL + jetons, modèle
   `config/supervision.env.exemple`) et `~/.config/claude-sandbox-infra/supervision/`
   (certificat client Grafana), tout en mode 600, montés en lecture seule dans le relais
   uniquement. Aucune adresse réelle d'outil dans ce dépôt.
6. **Lancement** : profil compose `supervision`, démarré par `run-infra.sh` seulement si
   `supervision.env` existe ; le script refuse un fichier lisible par d'autres. Arrêt :
   `docker compose -f docker/compose.infra.yml --profile supervision down`.
7. Le proxy de sortie (`squid.conf`) **n'est pas modifié** : aucun domaine d'outil n'y est
   ajouté. `claude-infra` reçoit `NO_PROXY=supervision-ro` pour joindre le relais en direct.

## Comptes et jetons à créer par l'opérateur

Rien n'est créé par ce dépôt. Pour chacun : compte **dédié** au Claude isolé (nom explicite,
ex. `claude-isole-lecture`), jamais un compte personnel ; date d'expiration quand l'outil le
permet ; révocation = supprimer le jeton puis relancer le relais.

1. **Grafana** — *Administration → Users and access → Service accounts* : créer un compte de
   service, rôle **Viewer**, sans permission supplémentaire sur dossier ou source ; lui créer
   un jeton (avec expiration). → `GRAFANA_TOKEN`.
   Certificat client : un certificat **dédié** au Claude isolé, émis par l'autorité acceptée
   par le frontal Grafana (révocable séparément de celui de l'opérateur), déposé en
   `supervision/grafana-client.crt` et `supervision/grafana-client.key`, clé **sans
   phrase de passe** (nginx doit la lire au démarrage) — d'où le mode 600 et le montage en
   lecture seule dans le seul relais.
2. **Alertmanager** — aucun compte (l'outil n'a pas d'authentification). Seule l'URL est à
   fournir ; la machine qui fait tourner le relais doit pouvoir la joindre (voir « Non
   vérifié »).
3. **GoAlert** — clé API GraphQL d'administration (*Admin → API Keys*), fonction
   expérimentale : le serveur doit tourner avec le drapeau `gql-api-keys` (PR GoAlert
   #3274 ; modèle de clé dans le paquet `apikey`, v0.32). Rôle **User** (pas Admin) ;
   politique : **uniquement des champs de lecture** (type `Query` : alertes, services,
   politiques d'escalade, plannings, rotations, utilisateurs — noms exacts à prendre dans
   le schéma GraphQL de l'instance, non vérifiés ici ; le test utilise `alerts`) —
   **aucun champ de `Mutation`** ; expiration. → `GOALERT_TOKEN`.
4. **Semaphore** — utilisateur dédié (non administrateur), ajouté avec le rôle **Guest** à
   chaque projet dont l'historique doit être lisible ; se connecter avec lui et créer un
   jeton d'API (*profil → API tokens* ou `POST /api/user/tokens`). → `SEMAPHORE_TOKEN`.

Puis : `chmod 600` sur tous les fichiers, `./scripts/run-infra.sh` (lance le relais), et
`./scripts/test-supervision.sh`.

## Conséquences

- Lecture seule effective même pour Alertmanager, sans dépendre de la discipline du modèle.
- GoAlert est le seul outil dont la lecture seule repose sur l'outil lui-même (politique de
  la clé) : à vérifier dans l'interface après création (étape manuelle du test).
- Ajouter un chemin ou une écriture = modifier le gabarit, donc une PR relisible ; les
  écritures (silence, acquittement, lancement) restent une décision à part (hors issue #4).
- Le relais est un composant de plus à maintenir (image épinglée à mettre à jour).
- Les jetons sont visibles par qui peut lire l'environnement du conteneur relais sur l'hôte
  (`docker inspect`) : même niveau que le fichier en mode 600 de l'opérateur.

## Non vérifié à la rédaction

Docker n'a pas été lancé (règle du dépôt), aucun outil n'a été appelé. À vérifier au premier
test (`scripts/test-supervision.sh`) :
- démarrage du relais en système de fichiers lecture seule (gabarit rendu dans le `tmpfs`
  de `conf.d` ; filtre `NGINX_ENVSUBST_FILTER` vérifié dans le code de l'entrypoint de
  l'image, pas en exécution) ;
- **joignabilité des outils depuis le poste** : le relais sort par le réseau de l'hôte. Un
  outil seulement joignable depuis une machine de rebond ne le sera pas sans tunnel côté
  hôte — à constater, puis décider ;
- format d'en-tête attendu par les clés GoAlert (`Authorization: Bearer`, supposé) et
  héritage du rôle Guest par le jeton Semaphore (la documentation consultée ne le dit pas
  explicitement ; le relais bloque de toute façon toute méthode autre que `GET`).

Sources consultées le 2026-11-18 : code de `entrypoint/20-envsubst-on-templates.sh` de
l'image nginx unprivileged ; PR GoAlert #3274 et documentation du paquet
`github.com/target/goalert/apikey` ; documentation Semaphore UI « Team » (rôles Owner,
Manager, Task Runner, Guest) et « API ».

## Alternatives rejetées

- **Domaines des outils dans `egress-proxy`** : le Claude isolé détiendrait les jetons, et
  aucune barrière contre l'écriture sur Alertmanager.
- **MCP par outil** (Grafana, etc.) : plus riche, mais un serveur à auditer par outil, et la
  lecture seule dépendrait de chaque implémentation ; le relais couvre le besoin avec `curl`.
  Piste v2 si l'usage le justifie, derrière le même principe (secrets hors du Claude isolé).
- **Jetons montés dans `claude-infra`** : exposés dans les sessions et réutilisables.
