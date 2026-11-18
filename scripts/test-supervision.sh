#!/usr/bin/env bash
# Vérifie le relais lecture seule vers les outils de supervision (issue #4, ADR-007).
# Usage (sur l'hôte, après ./scripts/run-infra.sh une fois, configuration déposée) :
#   ./scripts/test-supervision.sh
#
# Les requêtes partent d'un conteneur jetable de la variante (même image, même réseau),
# comme le ferait le Claude isolé avec curl. Seuls des codes HTTP sont affichés, jamais un
# contenu ni un jeton. Les écritures testées sont refusées PAR LE RELAIS (403 nginx) : elles
# n'atteignent pas l'outil, même en cas d'échec du test côté outil.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/../docker/compose.infra.yml"
ENVF="$HOME/.config/claude-sandbox-infra/supervision.env"
R=http://supervision-ro

echec=0
ok()  { echo "OK      : $*"; }
ko()  { echo "ÉCHEC   : $*"; echec=1; }

# code <méthode> <url> [corps JSON] → code HTTP vu depuis un conteneur claude-infra jetable
code() {
    docker compose -f "$COMPOSE_FILE" run --rm --no-deps -T --entrypoint sh \
        -e M="$1" -e U="$2" -e B="${3:-}" claude-infra -c '
        if [ -n "$B" ]; then
            curl -s -o /dev/null -w "%{http_code}" --max-time 20 -X "$M" -H "Content-Type: application/json" -d "$B" "$U"
        else
            curl -s -o /dev/null -w "%{http_code}" --max-time 20 -X "$M" "$U"
        fi' || true
}
attendu() { # attendu <code voulu> <libellé> <méthode> <url> [corps]
    local c
    c="$(code "$3" "$4" "${5:-}")"
    [[ "$c" == "$1" ]] && ok "$2 → $c" || ko "$2 → $c (attendu $1)"
}

echo "=== Étape 1 : configuration et relais ==="
[[ -f "$ENVF" ]] || { ko "$ENVF absent (procédure : ADR-007)"; exit 1; }
docker compose -f "$COMPOSE_FILE" --profile supervision ps --status running supervision-ro | grep -q supervision-ro \
    && ok "supervision-ro tourne" || { ko "supervision-ro ne tourne pas (docker compose … --profile supervision logs supervision-ro)"; exit 1; }

echo "=== Étape 2 : lectures (jeton valide, outil joint) ==="
attendu 200 "Grafana  GET /api/search"        GET  "$R:8091/api/search?limit=1"
attendu 200 "Alertm.  GET /api/v2/status"     GET  "$R:8092/api/v2/status"
attendu 200 "GoAlert  POST /api/graphql"      POST "$R:8093/api/graphql" '{"query":"{ alerts(input:{first:1}) { nodes { id } } }"}'
attendu 200 "Semaph.  GET /api/projects"      GET  "$R:8094/api/projects"

echo "=== Étape 3 : écritures refusées par le relais ==="
attendu 403 "Alertm.  POST /api/v2/silences"  POST   "$R:8092/api/v2/silences" '{}'
attendu 403 "Alertm.  DELETE /api/v2/silence" DELETE "$R:8092/api/v2/silence/00000000-0000-0000-0000-000000000000"
attendu 403 "Grafana  POST /api/dashboards/db" POST  "$R:8091/api/dashboards/db" '{}'
attendu 403 "Semaph.  POST /api/project/1/tasks" POST "$R:8094/api/project/1/tasks" '{}'
attendu 403 "GoAlert  GET / (interface)"      GET    "$R:8093/"
attendu 403 "Grafana  GET / (interface)"      GET    "$R:8091/"

echo "=== Étape 4 : aucun accès direct aux outils depuis claude-infra ==="
# Seules les lignes *_URL sont lues (jamais les jetons).
for v in GRAFANA_URL ALERTMANAGER_URL GOALERT_URL SEMAPHORE_URL; do
    u="$(sed -n "s/^$v=//p" "$ENVF" | head -1 | tr -d '"'\''')"
    [[ -n "$u" ]] || { echo "INFO    : $v absent"; continue; }
    c="$(docker compose -f "$COMPOSE_FILE" run --rm --no-deps -T --entrypoint sh -e U="$u" claude-infra \
        -c 'curl -s -o /dev/null -w "%{http_code}" --noproxy "*" --max-time 5 "$U"' || true)"
    [[ "$c" == "000" ]] && ok "$v injoignable en direct" || ko "$v joignable en direct (code $c)"
done

echo "=== Étape 5 : à vérifier à la main (non testable sans écrire) ==="
echo "MANUEL  : GoAlert — la politique de la clé ne liste que des champs de lecture (aucune mutation)."
echo "MANUEL  : Semaphore — l'utilisateur du jeton a le rôle Guest dans chaque projet visible."
echo "MANUEL  : Grafana — le compte de service a le rôle Viewer, aucune permission en plus."

echo
[[ $echec -eq 0 ]] && echo "RÉSULTAT : tout est conforme (hors vérifications manuelles)" || echo "RÉSULTAT : au moins un échec"
exit $echec
