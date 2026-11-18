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

# Identité des commits faits dans ~/www/e (monté en écriture) : celle de l'hôte, transmise
# par l'environnement (voir compose.infra.yml) — rien n'est écrit dans ce dépôt.
GIT_AUTHOR_NAME="$(git config --global user.name || true)"
GIT_AUTHOR_EMAIL="$(git config --global user.email || true)"
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL
if [[ -z "$GIT_AUTHOR_NAME" || -z "$GIT_AUTHOR_EMAIL" ]]; then
    echo "AVERTISSEMENT : identité git globale absente — les commits échoueront dans le conteneur." >&2
fi

# Relais lecture seule vers les outils de supervision (ADR-007) : lancé seulement si
# l'opérateur a déposé sa configuration. Jetons et certificat restent dans ce relais ;
# ce script ne les lit pas, il vérifie seulement que personne d'autre ne peut les lire.
SUPERVISION="$HOME/.config/claude-sandbox-infra"
if [[ -f "$SUPERVISION/supervision.env" ]]; then
    mkdir -p "$SUPERVISION/supervision"
    lisibles="$(find "$SUPERVISION/supervision.env" "$SUPERVISION/supervision" -type f -perm /077 2>/dev/null || true)"
    if [[ -n "$lisibles" ]]; then
        echo "ERREUR : fichiers de supervision lisibles par d'autres (chmod 600 attendu) :" >&2
        echo "$lisibles" >&2
        exit 1
    fi
    docker compose -f "$COMPOSE_FILE" --profile supervision up -d supervision-ro
else
    echo "Supervision : $SUPERVISION/supervision.env absent — relais non lancé (ADR-007)." >&2
fi

# MCP chargés uniquement depuis config/mcp-infra.json (aucun autre, même déclaré dans le profil).
exec docker compose -f "$COMPOSE_FILE" run --rm claude-infra \
    --mcp-config /home/user/mcp-infra.json --strict-mcp-config "$@"
