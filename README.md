# RubyRT: Ruby (but mostly Rails) Review Thing

RubyRT is an opinionated but helpful and flexible AI code review tool for Ruby and Rails projects. It is heavily inspired by [Gito](https://github.com/Nayjest/Gito) and brings the same LLM-driven review workflow to Ruby codebases, with extra knowledge of Ruby-specific tooling such as RuboCop, Brakeman, Solargraph, and the Ruby LSP.

## Features

- AI-powered code review via any OpenAI-compatible LLM (powered by [ruby_llm](https://github.com/crmne/ruby_llm)).
- Ruby and Rails-aware review prompts out of the box.
- Reads project skills and rules from configurable directories (defaults to `.agents`, `.claude`, and `.cursor`).
- Supports auxiliary files (`aux_files`) for injecting individual files as extra context into review prompts.
- Configurable request timeouts, retries, and logging to fail fast on unreachable providers.
- Integrates static analysis tools starting with RuboCop, with room for Brakeman, Solargraph, and the Ruby LSP.
- Consumes MCP servers to extend review capabilities with custom tools.
- Runs as a GitHub Action composite action, posting feedback as precise PR comments and resolving stale comments automatically.

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
- `secrets.GITHUB_TOKEN` is provided automatically by GitHub Actions. It must have at least `pull-requests: write` permission (set in the workflow `permissions` block) so RubyRT can post review comments and resolve stale threads.
- If you want RubyRT to resolve its own stale review threads, the token also needs read access to the authenticated user. The default `GITHUB_TOKEN` in a PR workflow from the same repository has this access. In forks or heavily restricted environments, `GITHUB_TOKEN` may not be able to call `GET /user`; RubyRT will skip resolving stale threads and continue posting the new review.

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

## Development

```bash
bundle install
bundle exec rake
```

## License

MIT. See [LICENSE.txt](LICENSE.txt).
