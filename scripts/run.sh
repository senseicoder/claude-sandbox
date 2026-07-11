#!/usr/bin/env bash
# Lance une session Claude Code dans le conteneur isolé.
# Usage : ./scripts/run.sh [args claude...]
#
# Tout ~/www est monté d'office (voir docs/adr/ADR-003) — plus de variable
# WORKSPACE, plus de credentials Google natifs à préparer (voir ADR-002).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/../docker/compose.yml"

# Créer le dossier d'échange avant le bind mount (un dossier absent = erreur Docker) —
# convention ~/Work/cnt/<nom-conteneur>, réutilisable pour de futurs conteneurs.
mkdir -p "$HOME/Work/cnt/claude-sandbox"

# Vérifier que la clé API est disponible
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
    echo "ERREUR : variable ANTHROPIC_API_KEY non définie." >&2
    echo "Lancer avec : ANTHROPIC_API_KEY=sk-... ./scripts/run.sh" >&2
    exit 1
fi

# Lancer le conteneur
exec docker compose -f "$COMPOSE_FILE" run --rm claude "$@"
