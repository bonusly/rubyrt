# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Thingie is an opinionated, AI-powered code review CLI and GitHub Action for Ruby/Rails projects. It diffs a PR's changeset, sends each changed file to an LLM for review, optionally runs a "critic pass" that adversarially re-checks each finding, then posts inline PR comments and optionally auto-approves.

## Commands

```bash
bundle install          # install deps
bundle exec rake        # RuboCop + RSpec (default CI task)
bundle exec rspec       # tests only
bundle exec rspec spec/thingie/configuration_spec.rb:17  # single test by line
bundle exec rubocop     # lint
bundle exec rubocop -A  # auto-fix
```

## Architecture

The review pipeline flows through these modules in order:

1. **`CLI`** (`cli.rb`) — Thor commands wire everything together. `review` is the main command.
2. **`Configuration`** (`configuration.rb`) — 5-layer merge: bundled defaults → `.thingie/config.toml` → `~/.thingie/.env` → env vars → CLI flags. `prompt_vars` is deep-merged; all other keys override. Skills (markdown fragments from `.agents/`, `.claude/`, `.cursor/`) are lazy-loaded.
3. **`Changeset`** (`changeset.rb`) — Uses `Rugged` (libgit2) to compute the diff between two refs. Supports merge-base comparison, glob-pattern file filters, and an `--all` mode to review the full codebase.
4. **`Reviewer`** (`reviewer.rb`) — Orchestrates the pipeline. Runs file reviews concurrently via `Async` fibers (bounded by `max_concurrent_tasks`). Aggregates errors without halting other files.
5. **PromptBuilder** (`prompt_builder.rb`) — Renders ERB templates (`review.erb`, `verify.erb`) with config vars and skills merged in.
6. **`LlmClient`** (`llm_client.rb`) — Wraps `ruby_llm`. Registers LSP/file tools for tool-use, handles retries and per-request timeout, uses structured output (schema → JSON).
7. **`IssueParser`** (`issue_parser.rb`) — Validates LLM JSON against `IssueSchema` and converts `RawIssue` → `Issue`.
8. **`PostProcessor`** (`post_processor.rb`) — Filters by `max_confidence` and `max_severity` thresholds before the critic pass.
9. **`CodeEnricher`** (`code_enricher.rb`) — Adds the actual affected code snippet and a syntax hint to each issue.
10. **`Verifier`** (`verifier.rb`) — Critic pass: re-runs each surviving finding through a skeptical LLM call. Drops findings it can't uphold. Fails open — unparseable verdict keeps the finding and records a warning.
11. **`ReportRenderer`** — Renders CLI (colored) or Markdown output from a `Report`.

**GitHub integration** (`github/`):
- `Commenter` — Posts/updates line-level PR comments via Octokit. Collapses stale Thingie threads before reposting.
- `Approver` — Evaluates PR against configured thresholds and submits an Approve review.
- `GraphQLClient` — Resolves stale review threads via GraphQL mutation (requires a user PAT; `GITHUB_TOKEN` cannot do this).

**LSP integration** (`lsp/`):
- `Client` — JSON-RPC-over-stdio client; spawns the LSP server (e.g. `ruby-lsp`) and calls `workspace/symbol`.
- `SymbolTool` — Wraps the client as a `ruby_llm` tool so the LLM can verify method/class existence during review, reducing hallucinated "undefined method" findings.

## Key Domain Concepts

- **Severity** 1–4: 1 = Critical, 4 = Low. Lower is stricter.
- **Confidence** 1–4: 1 = Highest certainty. Lower is stricter.
- **Tags**: `bug`, `security`, `performance`, `readability`, `maintainability`, `overcomplexity`, `language`, `architecture`, `compatibility`, `deprecation`, `anti-pattern`, `naming`, `code-style`.
- `pr` is allowed as a parameter name in RuboCop config (overrides default exclusion).
- RuboCop limits: 65-line methods, 120-line classes, 120-char lines.
- Block length cop is disabled for specs and gemspec.

## Configuration

Project config lives in `.thingie/config.toml`. Key sections:

```toml
provider = "openai"           # or anthropic, gemini, etc.
model = "gpt-4o"
llm_api_key = "..."           # or set LLM_API_KEY env var

[verify]
enabled = true
model = "anthropic/claude-opus-4.8"  # optional stronger model for critic pass

[lsp.ruby]
command = ["ruby-lsp"]
extensions = [".rb", ".rake"]

[approve]
enabled = false
max_changes = 500
max_severity = 3
protected_paths = ["app/billing/**"]

[post_process]
max_confidence = 1
max_severity = 3
```

Skills are `.md` files in `skill_directories` (default: `.agents`, `.claude`, `.cursor`) injected as system instructions.
