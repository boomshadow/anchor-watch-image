FROM node:24-alpine

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

RUN apk add --no-cache git curl bash jq yq

WORKDIR /opt/sdk
COPY package.json .
RUN npm install \
    && ln -s /opt/sdk/node_modules /node_modules

RUN curl -fsSL https://claude.ai/install.sh | bash

ENV PATH="/root/.local/bin:${PATH}"
