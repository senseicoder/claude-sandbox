FROM node:20-slim

# Tous les MCP externes (Gmail, Drive, Calendar, Jira, IMAP, Freebox, infra) sont
# désormais servis en réseau par mcp-services — plus aucun MCP natif ni credential
# dans cette image (voir docs/adr/ADR-002-migration-mcp-services.md).
RUN npm install -g \
        @anthropic-ai/claude-code \
    && apt-get update && apt-get install -y --no-install-recommends \
        git \
        curl \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# node:20-slim fournit déjà un utilisateur "node" en UID 1000 — collision avec le
# useradd suivant si on ne le retire pas d'abord (même piège que google-shared/Dockerfile
# dans mcp-services).
RUN userdel -r node

# Créer un utilisateur non privilégié (uid 1000)
RUN useradd -m -u 1000 -s /bin/bash user

# Répertoires de travail — créés ici pour que l'utilisateur en soit propriétaire.
# www et le vault Obsidian sont montés à un chemin identique à l'hôte (pas de
# renommage /workspace) pour ne pas casser les chemins absolus référencés dans les
# fichiers (CLAUDE.md, wiki, todo...) — voir docs/adr/ADR-003.
RUN mkdir -p /home/user/.claude /home/cedric/www /home/cedric/Sync/Central/Dossiers/obsidian /exchange && \
    chown -R user:user /home/user /home/cedric /exchange

# Passer à l'utilisateur non privilégié
USER user
WORKDIR /home/cedric/www

# Variables d'environnement Claude Code
ENV HOME=/home/user
ENV CLAUDE_CONFIG_DIR=/home/user/.claude

# Point d'entrée : Claude Code
ENTRYPOINT ["claude"]
CMD ["--help"]
