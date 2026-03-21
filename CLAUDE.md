# Claude instructions

This repo builds and publishes a Docker image used by Anchored Development
drift detection CI jobs. The image pre-installs Claude Code on `node:24-alpine`
so consuming pipelines don't need to install it on every run.

## Files

- `Dockerfile` — the image definition
- `.gitlab-ci.yml` — builds and pushes the image to GitLab Container Registry

## Conventions

- Keep the image minimal. Only add packages required at runtime.
- The image is rebuilt only when the Dockerfile changes on the default branch.
- Claude Code is installed via the official install script (`https://claude.ai/install.sh`).
