# diagnostic-tool — lightweight Dockerized Bash diagnostic CLI
FROM alpine:3.20

# Install only what the CLI needs: bash, coreutils-ish tools, network utils
RUN apk add --no-cache \
    bash \
    coreutils \
    procps \
    iproute2 \
    iputils \
    bind-tools

WORKDIR /app

# Application scripts
COPY app/diagnostic.sh app/health-check.sh /app/

# Ensure scripts are executable
RUN chmod +x /app/diagnostic.sh /app/health-check.sh

# Optional healthcheck used by orchestrators
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD ["/app/health-check.sh"]

# CLI entry: pass subcommands as container args
#   docker run --rm diagnostic-tool system
#   docker run --rm diagnostic-tool network example.com
ENTRYPOINT ["/app/diagnostic.sh"]
CMD ["help"]
