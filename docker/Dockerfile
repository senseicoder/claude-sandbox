FROM node:20-slim

# Installer Claude Code + MCP natifs (gmail, gdrive-pro)
# Évite de passer par SSH vers mnementh7 pour ces deux MCP
RUN npm install -g \
        @anthropic-ai/claude-code \
        @gongrzhe/server-gmail-autoauth-mcp \
        @piotr-agier/google-drive-mcp \
    && apt-get update && apt-get install -y --no-install-recommends \
        git \
        curl \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Créer un utilisateur non privilégié (uid 1000)
RUN useradd -m -u 1000 -s /bin/bash user

# Répertoires de travail — créés ici pour que l'utilisateur en soit propriétaire
RUN mkdir -p /home/user/.claude /workspace /exchange && \
    chown -R user:user /home/user /workspace /exchange

# Passer à l'utilisateur non privilégié
USER user
WORKDIR /workspace

# Variables d'environnement Claude Code
ENV HOME=/home/user
ENV CLAUDE_CONFIG_DIR=/home/user/.claude

# Point d'entrée : Claude Code
ENTRYPOINT ["claude"]
CMD ["--help"]
