# Proxy de sortie dédié pour claude-sandbox — seule porte vers Internet (api.anthropic.com
# uniquement, voir squid.conf). Dual-homed : mcp-sandbox-net (joignable par claude) +
# egress-net (sa propre sortie Internet réelle).
FROM ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends squid \
    && rm -rf /var/lib/apt/lists/*

COPY squid.conf /etc/squid/squid.conf

EXPOSE 3128

ENTRYPOINT ["squid", "-N", "-d", "1"]
