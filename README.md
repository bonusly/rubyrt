# RubyRT: Ruby (but mostly Rails) Review Thing

RubyRT is an opinionated but helpful and flexible AI code review tool for Ruby and Rails projects. It is heavily inspired by [Gito](https://github.com/Nayjest/Gito) and brings the same LLM-driven review workflow to Ruby codebases, with extra context pulled from the Ruby LSP.

## Features

- AI-powered code review via any OpenAI-compatible LLM (powered by [ruby_llm](https://github.com/crmne/ruby_llm)).
- Ruby and Rails-aware review prompts out of the box.
- Reads project skills and rules from configurable directories (defaults to `.agents`, `.claude`, and `.cursor`).
- Supports auxiliary files (`aux_files`) for injecting individual files as extra context into review prompts.
- Configurable request timeouts, retries, and logging to fail fast on unreachable providers.
- Pulls extra context from language servers (LSP) during review — ruby-lsp first, any LSP via config. (Run static analyzers like RuboCop as a separate step.)
- Consumes MCP servers to extend review capabilities with custom tools.
- Runs as a GitHub Action composite action, posting feedback as precise PR comments and (with a suitable token) resolving stale review threads automatically.

## Quickstart (after release)

Add to your repository:

```yaml
# .github/workflows/rubyrt-review.yml
name: "RubyRT Review"
on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  review:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: Bonusly/rubyrt/.github/actions/rubyrt@v1
        with:
          api_key: ${{ secrets.LLM_API_KEY }}
          provider: openrouter
          model: moonshotai/kimi-k2.6
```

### Ruby version and run command

- **`ruby_version`** — Ruby the action installs to run RubyRT. Defaults to `3.4`.
- **`rubyrt_command`** — how the CLI is invoked. Defaults to `rubyrt`. Set it to `bundle exec rubyrt`, `direnv exec . rubyrt`, etc. when your environment needs it.
- **`rubyrt_version`** — gem version to install (`local` builds from the checked-out repo). Set to `skip` to install nothing when `rubyrt_command` already provides RubyRT (e.g. it's in your Gemfile).

```yaml
      - uses: Bonusly/rubyrt/.github/actions/rubyrt@v1
        with:
          api_key: ${{ secrets.LLM_API_KEY }}
          ruby_version: "3.3"
          rubyrt_command: bundle exec rubyrt
          rubyrt_version: skip   # rubyrt comes from the project's Gemfile
```

### Required secrets and permissions

- `secrets.LLM_API_KEY`: Your LLM provider API key.
- `secrets.GITHUB_TOKEN` is provided automatically by GitHub Actions. It must have at least `pull-requests: write` permission (set in the workflow `permissions` block) so RubyRT can post review comments.
- Want comments to post under a custom name and avatar instead of "github-actions"? See **Posting as a GitHub App** below.
- Resolving stale review threads needs an **extra** token — see **Resolving stale review threads** below. The default `GITHUB_TOKEN` cannot do it.

### Posting as a GitHub App (custom name and avatar)

By default RubyRT posts as **github-actions[bot]** (the workflow `GITHUB_TOKEN`). To post under your own bot name and avatar, authenticate with a **GitHub App installation token** and pass it as the action's `github_token` input — review comments then appear as **YourApp[bot]**.

1. Create the app: **Settings → Developer settings → GitHub Apps → New GitHub App** (under your org or account). Give it the name and avatar you want to see on comments.
   - **Repository permissions → Pull requests: Read and write.** (No webhook needed — uncheck **Active**.)
2. **Generate a private key** and note the **App ID**.
3. **Install the app** on the repositories that run RubyRT.
4. Store the **App ID** as a variable (e.g. `vars.RUBYRT_APP_ID`) and the private key as a secret (e.g. `secrets.RUBYRT_APP_PRIVATE_KEY`).
5. Mint an installation token with [`actions/create-github-app-token`](https://github.com/actions/create-github-app-token) and pass it as `github_token`:

```yaml
jobs:
  review:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: actions/create-github-app-token@v2
        id: app_token
        with:
          app-id: ${{ vars.RUBYRT_APP_ID }}
          private-key: ${{ secrets.RUBYRT_APP_PRIVATE_KEY }}
      - uses: Bonusly/rubyrt/.github/actions/rubyrt@v1
        with:
          api_key: ${{ secrets.LLM_API_KEY }}
          github_token: ${{ steps.app_token.outputs.token }}   # post as the app
          resolve_token: ${{ secrets.RUBYRT_RESOLVE_TOKEN }}    # resolve threads (PAT — see below)
```

> The app installation token posts comments fine, but **cannot resolve review threads** (`resolveReviewThread` rejects server-to-server tokens). If you also want stale threads auto-resolved, pair it with a user PAT in `resolve_token` as shown — see the next section.

### Resolving stale review threads

When RubyRT re-reviews a PR, it can mark its earlier threads as resolved once the issue is fixed or the line is outdated. This uses the GraphQL `resolveReviewThread` mutation, which **requires a user-to-server token (a personal access token).**

> **The default `GITHUB_TOKEN` cannot do this, and neither can a GitHub App.** Both are *server-to-server* tokens, and `resolveReviewThread` returns `Resource not accessible by integration` for them even with `pull-requests: write` — including the installation token from `actions/create-github-app-token`. Only a user PAT works.

To enable auto-resolving, create a PAT and pass it via the `resolve_token` action input (or the `RUBYRT_RESOLVE_TOKEN` env var / `--resolve-token` flag for the `github-comment` CLI). If you don't set one, RubyRT skips resolving and still posts the new review.

1. Create a token as a user with write access to the repo:
   - **Fine-grained PAT** (recommended): **Settings → Developer settings → Personal access tokens → Fine-grained tokens**, scope it to the repo, and grant **Repository permissions → Pull requests: Read and write**; or
   - **Classic PAT** with the `repo` scope.
2. Store it as a repository (or org) secret, e.g. `secrets.RUBYRT_RESOLVE_TOKEN`.
3. Pass it to the action:

```yaml
jobs:
  review:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: Bonusly/rubyrt/.github/actions/rubyrt@v1
        with:
          api_key: ${{ secrets.LLM_API_KEY }}
          provider: openrouter
          model: moonshotai/kimi-k2.6
          resolve_token: ${{ secrets.RUBYRT_RESOLVE_TOKEN }}
```

Threads are resolved as whichever user owns the PAT. (A machine/bot user account is a good fit if you don't want resolutions attributed to a person.)

### Configuration options

RubyRT reads configuration from layers (later layers override earlier ones):

1. `lib/rubyrt/config/default.toml` bundled with the gem.
2. `.rubyrt/config.toml` in your project root.
3. `~/.rubyrt/.env` (loaded into your environment).
4. Environment variables.
5. CLI flags.

Key settings:

| Setting | Default | Config key | Environment variable | CLI flag |
|---|---|---|---|---|
| LLM provider | `openai` | `provider` | `LLM_PROVIDER` | `-p`, `--provider` |
| LLM model | `gpt-4o` | `model` | `LLM_MODEL` | `-m`, `--model` |
| API key | — | `llm_api_key` | `LLM_API_KEY` | — |
| API base URL | provider default | `llm_api_base` | `LLM_API_BASE` | — |
| Request timeout (seconds) | `120` | `request_timeout` | `LLM_REQUEST_TIMEOUT` | — |
| Retries | `3` | `retries` | `LLM_RETRIES` | — |
| Log file | stdout | `log_file` | `RUBYRT_LOG_FILE` | — |
| Log level | `info` | `log_level` | `RUBYRT_LOG_LEVEL` | — |
| Skill directories | `.agents`, `.claude`, `.cursor` | `skill_directories` | — | — |
| Auxiliary files | `[]` | `aux_files` | — | — |

Supported providers match whatever RubyLLM supports, including `openai`, `anthropic`, `gemini`, `ollama`, `deepseek`, `openrouter`, `mistral`, `perplexity`, `xai`, `azure`, `bedrock`, `vertexai`, and `gpustack`.

Example `.rubyrt/config.toml`:

```toml
provider = "anthropic"
model = "claude-sonnet-4"
request_timeout = 60
log_file = "log/rubyrt.log"
log_level = "debug"

# Add extra files as context to every review prompt
aux_files = ["docs/conventions.md", ".rubyrt/style-guide.md"]

# Customize which directories are scanned for skill fragments
skill_directories = [".agents", ".github"]
```

### Skills and auxiliary files

RubyRT automatically discovers markdown files (`.md`) in skill directories and injects them as additional rules in every review prompt. By default it scans `.agents/`, `.claude/`, and `.cursor/` in the project root. Override this with the `skill_directories` config key.

For individual files (rather than whole directories), use `aux_files` to list paths relative to the project root. Their contents are included as extra context in every review prompt:

```toml
aux_files = ["docs/coding-standards.md", "docs/security-rules.md"]
```

### Logging

Set `log_file` to a file path to persist RubyLLM request logs for debugging. Set `log_level` to `debug` to see full request and response bodies. Valid levels are `debug`, `info`, `warn`, `error`, and `fatal`.

### Structured output

RubyRT uses [structured output](https://rubyllm.com/available-models/#structured-output-469) to ensure the LLM returns valid JSON. Not all models support this feature; see the [RubyLLM available models page](https://rubyllm.com/available-models/#structured-output-469) for a list of compatible models. For models that don't support structured output, RubyRT falls back to parsing the response as JSON from the prompt instructions.

## Development

```bash
bundle install
bundle exec rake
```

## License

MIT. See [LICENSE.txt](LICENSE.txt).
