# anchor-watch-image

Pre-built Docker image for running [Anchored Development](https://anchored-dev.org) drift detection in CI pipelines.

## What's in the image

- `node:24-alpine` base
- [Claude Code](https://claude.ai) CLI (pre-installed)
- Common tools Claude may need during drift analysis (see [Dockerfile](Dockerfile))

## Usage

Reference the image in your CI pipeline instead of installing Claude Code on every run:

```yaml
anchor-watch:
  image: registry.gitlab.com/boomshadow/anchor-watch-image:latest
  before_script:
    - cd ci && npm install && cd ..
  script:
    - node ci/drift-detector.mjs
```

## Building locally

```sh
docker build -t anchor-watch-image .
```

## License

[MPL-2.0](LICENSE)
