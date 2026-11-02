# devops-tool — lightweight image for the Assignment 3 Bash CLI
FROM alpine:3.20

RUN apk add --no-cache \
    bash \
    coreutils \
    procps \
    iproute2 \
    iputils \
    bind-tools \
    busybox-extras

WORKDIR /app

COPY app/app.sh /app/app.sh

RUN chmod +x /app/app.sh \
    && ln -sf /app/app.sh /usr/local/bin/devops-tool

# Prefer calling the CLI by image args
ENTRYPOINT ["/app/app.sh"]
CMD ["help"]
