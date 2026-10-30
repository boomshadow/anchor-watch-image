# Pre-commit tooling

Optional tooling for a repository that follows [Anchored Development](https://anchored-dev.org): a
local pre-push drift check and an index freshness check, published as [pre-commit](https://pre-commit.com)
hooks. SPEC-000 is tool-agnostic, and any mechanism that detects drift satisfies it. This one gives
feedback before a push, and on platforms the GitLab CI job does not cover.

The tools are consumed by reference, pinned to a release tag of this repository, never copied. A hook
that runs on every push should be updated by a version bump, not by hand-merging a forked copy.

## Usage

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/boomshadow/anchor-watch-image
    rev: <version>
    hooks:
      - id: gen-index-check
      - id: drift-check
```

```sh
pre-commit install --hook-type pre-push
```

| Hook | Stage | What it does |
|---|---|---|
| `gen-index-check` | pre-push | Fails when `docs/specs/INDEX.md` or `docs/decisions/INDEX.md` is stale |
| `gen-index` | manual | Rewrites both indexes: `pre-commit run --hook-stage manual gen-index` |
| `drift-check` | pre-push | Asks `claude -p` whether the pushed change disagrees with the specs and ADRs |

GitHub Actions can run the index check, which needs no model and no secret:

```yaml
- uses: actions/checkout@<sha>
- uses: boomshadow/anchor-watch-image/.github/actions/check@<sha>
```

The drift check stays where a project already runs drift detection. On GitLab that is the
`anchor-watch` job in this image.

## gen-index

Generates both `INDEX.md` files from frontmatter, in the same table format as the spec and adr
skills' generators. An empty directory yields a header-only index, so a repository can start with no
specs or ADRs. `--check` writes nothing and exits 1 when either index is stale.

It uses only the Python standard library, so a hook or CI job installs nothing. In exchange,
frontmatter must stay simple: one `key: value` per line and tags as an inline list. Constructs it
cannot read exactly (trailing comments, escaped single quotes, other escapes, bare booleans or
numbers) are rejected rather than guessed.

It rejects what the framework rejects: missing required fields, `draft` status, non-lowercase tags,
duplicate numbers, and ADRs missing Context, Decision or Consequences. The generated-by header
comment is neither compared nor rewritten, so an index written by either generator passes the check
and is left alone.

## drift-check

Compares the range from the merge base of `DRIFT_BASE` and `DRIFT_HEAD_REF` to `DRIFT_HEAD_REF`
against the repository's specs, ADRs, tests and navigation aids.

| Variable | Default |
|---|---|
| `DRIFT_BASE` | The remote's default branch, else `main` on that remote |
| `DRIFT_HEAD_REF` | The ref pre-commit reports as pushed, else `HEAD` |
| `DRIFT_AGENT_FILE` | The repository's `.claude/agents/drift-detector.md` as it is at `DRIFT_BASE` |
| `DRIFT_MAX_DIFF_BYTES` | `200000` |
| `DRIFT_SKIP_PATHS` | Common lock files. Entries name a file, a directory or a glob, matched at any depth; set it empty to skip nothing |
| `CLAUDE_BIN` | `claude` |

- **The detection criteria have one source.** The check runs the same drift-detector agent
  instructions as the repository's CI, so local and CI verdicts are judged by the same text.
- **The instructions come from the baseline.** A change cannot rewrite the criteria it is judged
  by; an edit to them applies once it is merged. A repository adopting the framework merges its
  agent file first, or names one with `DRIFT_AGENT_FILE`.
- **The model can only read.** Claude Code gets the Read, Glob and Grep tools and nothing else,
  anything outside them is denied without asking, and settings, hooks and MCP servers are ignored,
  because the commit under review controls them. Provider configuration (Bedrock, Vertex) must come
  from the environment for the same reason.
- **The diff and the files describe the same commit.** The agent reads a temporary export of
  `DRIFT_HEAD_REF`, not the working tree. The export ignores repository attributes, leaves the
  caller's index alone and runs no repository hooks.
- **Repository text is data.** The diff sits between markers carrying a per-run random token, so it
  cannot end its own delimiting. The diff does not depend on the developer's git configuration or
  the repository's attributes, so a commit cannot hide its change.
- **It refuses rather than guesses.** A diff over the size limit is refused, never truncated, because
  a verdict on part of a change reads as a verdict on all of it. Output that is neither a finding nor
  the no-drift statement is no verdict.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | No drift, or nothing relevant changed (the model is not called) |
| 1 | The detector reported at least one finding |
| 2 | No verdict: not in a repository, unresolvable refs, a failing git command, missing required files or instructions, missing runner, runner failure, oversized diff, or unrecognised output |

Findings win over a no-drift statement, so contradictory output never passes. Only exit code 1 means
the artifacts and the code disagree. `SKIP=drift-check git push` skips the hook once: a client-side
hook is advisory, and catches honest drift rather than enforcing policy.

### Known gaps

- The verdict comes from a model and is not deterministic. The stub-runner tests prove the plumbing,
  not the judgment.
- The verdict is parsed from the agent's prose, where the CI script uses structured output. The two
  formats are maintained separately.
- Sizes are counted in bytes, where CI counts characters, so a diff heavy in non-ASCII text can be
  refused locally that CI accepts.
- Submodule content is absent from the export. Only the first pushed ref is checked when a push
  carries several. There is no timeout around the model call.

## Design choices

**Hosted here, not in the framework or example repository.** The example repository is what teams
copy from, and copying a hook forks it. The framework repository governs the specification and its
website. This repository already ships the drift-detection runtime under semantic versioning, which
is what a pinned hook needs.

**A second index generator.** The skills' generators need PyYAML, which every hook environment and
minimal CI image would then install. The accepted cost is a second generator whose output format must
be kept in step, which `--check` passing on indexes written by either one is meant to catch.

**The Claude CLI, not the Agent SDK.** Running the CI script locally needs Node and an SDK install in
every consumer; the CLI is already on the machines that run the check.

**No shell for the agent, so no summary of large diffs.** CI hands the agent a summary of an
oversized diff and lets it read hunks through `git`. Locally the agent has no shell, so it could not
read what it was not given, and the diff is refused instead.

## Tests

`test/gen-index.sh` and `test/drift-check.sh` run in throwaway repositories with stub runners, so no
model is called. The `test:tools` CI job runs both. The hook manifest and the composite action have no
test.
