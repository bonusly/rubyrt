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

### Required secrets and permissions

- `secrets.LLM_API_KEY`: Your LLM provider API key.
- `secrets.GITHUB_TOKEN` is provided automatically by GitHub Actions. It must have at least `pull-requests: write` permission (set in the workflow `permissions` block) so RubyRT can post review comments.
- Resolving stale review threads needs an **extra** token — see below. The default `GITHUB_TOKEN` cannot do it.

### Resolving stale review threads

When RubyRT re-reviews a PR, it can mark its earlier threads as resolved once the issue is fixed or the line is outdated. This uses the GraphQL `resolveReviewThread` mutation, which the default `GITHUB_TOKEN` **cannot** call — it returns `Resource not accessible by integration` even with `pull-requests: write`, because it is a server-to-server token and that mutation requires a user-to-server token.

To enable auto-resolving, pass a token that can — via the `resolve_token` action input (or the `RUBYRT_RESOLVE_TOKEN` env var / `--resolve-token` flag for the `github-comment` CLI). If you don't set one, RubyRT simply skips resolving and still posts the new review.

A **GitHub App** is the recommended source for this token (scoped, org-manageable, and not tied to a personal account):

1. Create the app: **Settings → Developer settings → GitHub Apps → New GitHub App** (under your org or account).
   - **Repository permissions → Pull requests: Read and write.** No other permissions are needed.
   - Uncheck **Active** under Webhook (RubyRT doesn't receive events).
2. After creating it, **generate a private key** (bottom of the app's settings page) and note the **App ID** (top of the page).
3. **Install the app** on the repositories that run RubyRT (**Install App** in the app's sidebar).
4. Store the credentials on the repo/org:
   - App ID as a variable, e.g. `vars.RUBYRT_APP_ID`.
   - Private key (the full `.pem` contents) as a secret, e.g. `secrets.RUBYRT_APP_PRIVATE_KEY`.
5. Mint a token in the workflow with [`actions/create-github-app-token`](https://github.com/actions/create-github-app-token) and hand it to RubyRT as `resolve_token`:

```yaml
jobs:
  review:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
    steps:
      - uses: actions/checkout@v7
        with:
          ref: ${{ github.event.pull_request.head.sha }}
      - uses: actions/create-github-app-token@v2
        id: app_token
        with:
          app-id: ${{ vars.RUBYRT_APP_ID }}
          private-key: ${{ secrets.RUBYRT_APP_PRIVATE_KEY }}
      - uses: Bonusly/rubyrt/.github/actions/rubyrt@v1
        with:
          api_key: ${{ secrets.LLM_API_KEY }}
          provider: openrouter
          model: moonshotai/kimi-k2.6
          resolve_token: ${{ steps.app_token.outputs.token }}
```

**Simpler alternative — a Personal Access Token.** If you don't want an app, create a fine-grained PAT scoped to the repo with **Pull requests: Read and write** (or a classic PAT with the `repo` scope), store it as `secrets.RUBYRT_RESOLVE_TOKEN`, and pass `resolve_token: ${{ secrets.RUBYRT_RESOLVE_TOKEN }}`. Threads will then be resolved as that user rather than the app.

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
