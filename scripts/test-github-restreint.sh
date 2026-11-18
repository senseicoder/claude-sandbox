#!/usr/bin/env bash
# Vérifie que le MCP GitHub de la variante infra refuse le merge (issue #2, ADR-005).
# Usage (sur l'hôte, après ./scripts/run-infra.sh une fois, jeton déposé) :
#   ./scripts/test-github-restreint.sh <propriétaire/dépôt> <numéro de PR de test>
# La PR de test doit être ouverte et fusionnable : si le refus ne marchait pas, elle serait
# fusionnée — prendre une PR jetable (branche de test sur un dépôt sans enjeu).
#
# Les requêtes partent d'un conteneur jetable sur mcp-sandbox-net, comme le ferait le Claude
# isolé avec curl (il a Bash) : c'est la barrière côté serveur qui est testée, pas Claude Code.
# Aucun jeton n'est lu ni affiché ici : il n'est que dans le conteneur mcp-github-restreint.

set -euo pipefail

DEPOT="${1:?usage : $0 <propriétaire/dépôt> <numéro de PR de test>}"
PR="${2:?usage : $0 <propriétaire/dépôt> <numéro de PR de test>}"
PROPRIO="${DEPOT%%/*}"
NOM="${DEPOT#*/}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/../docker/compose.infra.yml"

# Client MCP minimal (streamable HTTP) exécuté dans un conteneur jetable de l'image du sandbox.
# $1 = en-têtes supplémentaires (ex. « -H X-MCP-Tools:merge_pull_request »), $2 = requête JSON-RPC.
read -r -d '' CLIENT <<'EOF' || true
set -eu
U=http://mcp-github-restreint:8200/mcp
H='-H Content-Type:application/json -H Accept:application/json,text/event-stream'
SID=$(curl -s --noproxy '*' -D - -o /dev/null $H $EXTRA -X POST "$U" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test-github-restreint","version":"1"}}}' \
  | tr -d '\r' | sed -n 's/^[Mm]cp-[Ss]ession-[Ii]d: //p')
S=""; [ -n "$SID" ] && S="-H Mcp-Session-Id:$SID"
curl -s --noproxy '*' $H $S $EXTRA -X POST "$U" -d '{"jsonrpc":"2.0","method":"notifications/initialized"}' >/dev/null
curl -s --noproxy '*' $H $S $EXTRA -X POST "$U" -d "$REQ"
EOF

mcp() {
    docker compose -f "$COMPOSE_FILE" run --rm --no-deps -T --entrypoint sh \
        -e EXTRA="$1" -e REQ="$2" claude-infra -c "$CLIENT"
}

echec=0
ok()  { echo "OK      : $*"; }
ko()  { echo "ÉCHEC   : $*"; echec=1; }

echo "=== Étape 1 : service lancé ==="
docker compose -f "$COMPOSE_FILE" --profile github ps --status running mcp-github-restreint | grep -q mcp-github-restreint \
    && ok "mcp-github-restreint tourne" || { ko "mcp-github-restreint ne tourne pas (lancer run-infra.sh, jeton déposé ?)"; exit 1; }

echo "=== Étape 2 : outils exposés ==="
LISTE="$(mcp "" '{"jsonrpc":"2.0","id":2,"method":"tools/list"}')"
for t in merge_pull_request delete_repository create_repository fork_repository delete_file; do
    grep -q "\"name\":\"$t\"" <<<"$LISTE" && ko "$t exposé" || ok "$t absent"
done
for t in create_branch push_files create_pull_request get_file_contents; do
    grep -q "\"name\":\"$t\"" <<<"$LISTE" && ok "$t présent" || ko "$t absent (attendu présent)"
done

echo "=== Étape 3 : merge refusé, y compris en le réclamant par en-tête ==="
APPEL="{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"merge_pull_request\",\"arguments\":{\"owner\":\"$PROPRIO\",\"repo\":\"$NOM\",\"pullNumber\":$PR}}}"
for extra in "" "-H X-MCP-Tools:merge_pull_request" "-H X-MCP-Toolsets:all -H X-MCP-Exclude-Tools:none"; do
    R="$(mcp "$extra" "$APPEL")"
    if grep -qi '"merged":true\|Pull Request successfully merged\|successfully merged' <<<"$R"; then
        ko "MERGE ACCEPTÉ (en-têtes : ${extra:-aucun}) — PR $DEPOT#$PR probablement fusionnée"
    else
        ok "merge refusé (en-têtes : ${extra:-aucun}) : $(grep -o '"message":"[^"]*"\|"text":"[^"]*"' <<<"$R" | head -1)"
    fi
done

echo "=== Étape 4 : état de la PR (doit rester ouverte) ==="
R="$(mcp "" "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"pull_request_read\",\"arguments\":{\"method\":\"get\",\"owner\":\"$PROPRIO\",\"repo\":\"$NOM\",\"pullNumber\":$PR}}}")"
grep -q '\\"merged\\":true\|"merged":true' <<<"$R" && ko "PR $DEPOT#$PR fusionnée" || ok "PR $DEPOT#$PR non fusionnée"

[ "$echec" = 0 ] && echo "=== RÉSULTAT : OK ===" || echo "=== RÉSULTAT : ÉCHEC — ne pas utiliser le MCP github de la variante ==="
echo "=== FIN SCRIPT ==="
exit "$echec"
