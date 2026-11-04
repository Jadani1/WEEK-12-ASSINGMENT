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
RUN chmod +x /app/app.sh

# Default: show help when no command is passed
ENTRYPOINT ["/app/app.sh"]
CMD ["help"]
