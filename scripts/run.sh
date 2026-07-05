#!/usr/bin/env bash
# Lance une session Claude Code dans le conteneur isolé.
# Usage : ./scripts/run.sh [args claude...]
#         WORKSPACE=~/www/e/mon-projet ./scripts/run.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/../docker/compose.yml"

# Créer les dossiers nécessaires avant le bind mount (un dossier absent = erreur Docker)
mkdir -p "$HOME/claude-exchange"
mkdir -p "$HOME/.config/google-drive-mcp"
mkdir -p "$HOME/.config/google-calendar-mcp"

# Vérifier que la clé API est disponible
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
    echo "ERREUR : variable ANTHROPIC_API_KEY non définie." >&2
    echo "Lancer avec : ANTHROPIC_API_KEY=sk-... ./scripts/run.sh" >&2
    exit 1
fi

# Lancer le conteneur
exec docker compose -f "$COMPOSE_FILE" run --rm claude "$@"
