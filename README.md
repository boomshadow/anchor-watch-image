# anchor-watch-image

Pre-built Docker image for running [Anchored Development](https://github.com/anchored-dev/anchored-development) drift detection in CI pipelines.

## What's in the image

- `node:24-alpine` base
- `git`, `curl`, `bash`
- [Claude Code](https://claude.ai) CLI (pre-installed)

## Usage

Reference the image in your CI pipeline instead of installing Claude Code on every run:

```yaml
anchor-watch:
  image: registry.gitlab.com/YOUR_GROUP/anchor-watch-image:latest
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
