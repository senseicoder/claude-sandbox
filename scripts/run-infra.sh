#!/usr/bin/env bash
# Lance une session Claude Code dans la variante « infra » (voir docs/adr/ADR-004).
# Usage : ./scripts/run-infra.sh [args claude...]
#
# Prérequis : mcp-services lancé (mcp-infra, mcp-google-pro, mcp-jira) ; profil dédié
# ~/.claude-infra connecté une fois sur l'hôte par abonnement (voir ci-dessous).
# Les scripts de collecte que le Claude isolé dépose dans infra-audit/ se lancent depuis
# infra-run, sur l'hôte (ADR-006) — jamais depuis ce conteneur.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/../docker/compose.infra.yml"
PROFIL="$HOME/.claude-infra"

# Dossiers montés : un dossier absent fait échouer le bind mount Docker.
mkdir -p "$HOME/Work/cnt/claude-sandbox-infra" "$PROFIL"
# Dossier lu par infra-run et son état .runner/ (monté en lecture seule par-dessus, ADR-006) :
# créés s'ils manquent (poste où infra-run n'a jamais tourné), sans toucher à leur contenu.
mkdir -p "$HOME/Sync/Central/Dossiers/claude/data/infra-audit/.runner"
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

# Identité des commits faits dans ~/www/e (monté en écriture) : celle de l'hôte, transmise
# par l'environnement (voir compose.infra.yml) — rien n'est écrit dans ce dépôt.
GIT_AUTHOR_NAME="$(git config --global user.name || true)"
GIT_AUTHOR_EMAIL="$(git config --global user.email || true)"
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL
if [[ -z "$GIT_AUTHOR_NAME" || -z "$GIT_AUTHOR_EMAIL" ]]; then
    echo "AVERTISSEMENT : identité git globale absente — les commits échoueront dans le conteneur." >&2
fi

# MCP chargés uniquement depuis config/mcp-infra.json (aucun autre, même déclaré dans le profil).
exec docker compose -f "$COMPOSE_FILE" run --rm claude-infra \
    --mcp-config /home/user/mcp-infra.json --strict-mcp-config "$@"
