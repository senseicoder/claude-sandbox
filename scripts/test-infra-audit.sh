#!/usr/bin/env bash
# Vérifie le montage infra-audit/ de la variante infra (issue #3, ADR-006).
# Usage (sur l'hôte, image construite, réseau mcp-sandbox-net présent) :
#   ./scripts/test-infra-audit.sh
#
# Les vérifications partent d'un conteneur jetable de la variante (même image, mêmes
# montages, sans egress-proxy), comme le ferait le Claude isolé avec Bash.
# Le fichier d'essai porte l'extension .tmp : infra-run ne lit que les *.sh, il ne le
# proposera donc jamais. Il est supprimé depuis l'hôte à la fin. Aucun contenu de log
# n'est affiché (un log peut contenir des données de production).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/../docker/compose.infra.yml"
AUDIT="$HOME/Sync/Central/Dossiers/claude/data/infra-audit"
CIBLE="/home/cedric/Sync/Central/Dossiers/claude/data/infra-audit"
ESSAI=".test-claude-sandbox-$$.tmp"

[[ "$AUDIT" == "$CIBLE" ]] || echo "AVERTISSEMENT : \$HOME de l'hôte n'est pas /home/cedric — les chemins des scripts différeront."

dans() {
    docker compose -f "$COMPOSE_FILE" run --rm --no-deps -T --entrypoint sh claude-infra -c "$1"
}

echec=0
ok()  { echo "OK      : $*"; }
ko()  { echo "ÉCHEC   : $*"; echec=1; }
trap 'rm -f "$AUDIT/$ESSAI"' EXIT

mkdir -p "$AUDIT/.runner"

echo "=== Étape 1 : écriture dans infra-audit/ ==="
if dans "echo essai > '$CIBLE/$ESSAI'" && [[ -f "$AUDIT/$ESSAI" ]]; then
    ok "fichier créé depuis le conteneur, visible sur l'hôte"
    proprio="$(stat -c %u "$AUDIT/$ESSAI")"
    [[ "$proprio" == "$(id -u)" ]] && ok "propriétaire uid $proprio = utilisateur de l'hôte (infra-run le traite comme les siens)" \
        || ko "propriétaire uid $proprio ≠ $(id -u)"
else
    ko "écriture impossible dans $CIBLE"
fi

echo "=== Étape 2 : .runner/ en lecture seule ==="
if dans "touch '$CIBLE/.runner/$ESSAI' 2>/dev/null"; then
    rm -f "$AUDIT/.runner/$ESSAI"
    ko "écriture possible dans .runner/ (journal d'infra-run falsifiable)"
else
    ok "écriture refusée dans .runner/"
fi
dans "ls '$CIBLE/.runner' >/dev/null" && ok ".runner/ lisible" || ko ".runner/ illisible"

echo "=== Étape 3 : rien d'autre du poste en écriture ==="
for p in /home/cedric/Sync/Central/Dossiers/claude/data /home/cedric/Sync /home/cedric; do
    if dans "touch '$p/$ESSAI' 2>/dev/null"; then ko "écriture possible dans $p"; else ok "écriture refusée dans $p"; fi
done

echo "=== Étape 4 : lecture des logs ==="
# Le nom du log n'est pas affiché non plus : seul compte le fait qu'il soit lisible.
if dans "f=\$(ls -t '$CIBLE'/*.log 2>/dev/null | head -1); [ -n \"\$f\" ] && head -c1 \"\$f\" >/dev/null"; then
    ok "un .log existant est lisible"
else
    echo "INFO    : aucun .log lisible trouvé (dossier vide sur ce poste ?)"
fi

echo "=== Étape 5 : aucun moyen d'exécuter sur les serveurs ==="
for c in ansible ansible-playbook ssh infra-run; do
    if dans "command -v $c >/dev/null"; then ko "$c présent dans le conteneur"; else ok "$c absent"; fi
done

echo
[[ $echec -eq 0 ]] && echo "RÉSULTAT : tout est conforme" || echo "RÉSULTAT : au moins un échec"
exit $echec
