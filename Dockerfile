FROM node:24-alpine

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

RUN apk add --no-cache git curl bash jq yq

RUN adduser -D anchor-watch
USER anchor-watch

RUN curl -fsSL https://claude.ai/install.sh | bash

ENV PATH="/home/anchor-watch/.local/bin:${PATH}"
