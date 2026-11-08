#!/usr/bin/env bash
# Lance une session Claude Code dans la variante « infra » (voir docs/adr/ADR-004).
# Usage : ./scripts/run-infra.sh [args claude...]
#
# Prérequis : mcp-services lancé (mcp-infra, mcp-google-pro, mcp-jira) ; profil dédié
# ~/.claude-infra connecté une fois sur l'hôte par abonnement (voir ci-dessous).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/../docker/compose.infra.yml"
PROFIL="$HOME/.claude-infra"

# Dossiers montés : un dossier absent fait échouer le bind mount Docker.
mkdir -p "$HOME/Work/cnt/claude-sandbox-infra" "$PROFIL"
chmod 700 "$PROFIL"

# Authentification par abonnement : jamais de clé API dans cette variante.
if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    echo "ERREUR : ANTHROPIC_API_KEY est définie — la variante infra n'utilise que l'abonnement." >&2
    echo "Relancer sans cette variable (unset ANTHROPIC_API_KEY)." >&2
    exit 1
fi
if [[ ! -s "$PROFIL/.credentials.json" ]]; then
    echo "Profil $PROFIL non connecté. Connexion unique, sur l'hôte :" >&2
    echo "  CLAUDE_CONFIG_DIR=$PROFIL claude    puis /login (compte claude.ai), puis /exit" >&2
    echo "Les identifiants sont alors dans $PROFIL/.credentials.json (mode 600)." >&2
    exit 1
fi

# CLAUDE.md du profil : copié une seule fois depuis le modèle, jamais écrasé.
if [[ ! -e "$PROFIL/CLAUDE.md" ]]; then
    cp "$SCRIPT_DIR/../config/CLAUDE-infra.md" "$PROFIL/CLAUDE.md"
fi

# MCP chargés uniquement depuis config/mcp-infra.json (aucun autre, même déclaré dans le profil).
exec docker compose -f "$COMPOSE_FILE" run --rm claude-infra \
    --mcp-config /home/user/mcp-infra.json --strict-mcp-config "$@"
