FROM node:24.14.0-trixie-slim@sha256:8c8f12cedb96c3b59642cf30d713943c2b223990c9919b96a141681f62e6e292

SHELL ["/bin/bash", "-eo", "pipefail", "-c"]

RUN apt-get update && apt-get install -y \
    git curl jq yq \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/sdk
COPY package.json package-lock.json ./
RUN npm ci \
    && ln -s /opt/sdk/node_modules /node_modules

RUN curl -fsSL https://claude.ai/install.sh | bash

ENV PATH="/root/.local/bin:${PATH}"
