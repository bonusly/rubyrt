# AGENTS.md

This file provides guidance to AI coding agents (Codex, Copilot, Cursor, etc.) when working with code in this repository.

## What This Is

RubyRT is an AI-powered code review CLI and GitHub Action for Ruby/Rails projects. It reviews PR changesets using LLMs, runs an optional adversarial "critic pass" to reduce false positives, and posts inline GitHub PR comments.

## Commands

```bash
bundle install                                           # install dependencies
bundle exec rake                                         # full CI: RuboCop + RSpec
bundle exec rspec                                        # tests only
bundle exec rspec spec/rubyrt/configuration_spec.rb:17  # single test by line number
bundle exec rubocop                                      # lint
bundle exec rubocop -A                                   # auto-fix lint
```

Always run `bundle exec rake` before committing to ensure both linting and tests pass.

## Architecture

The review pipeline runs in this order:

1. **CLI** (`lib/rubyrt/cli.rb`) — Thor commands. `review` is the primary command.
2. **Configuration** (`lib/rubyrt/configuration.rb`) — 5-layer merge: bundled defaults → `.rubyrt/config.toml` → `~/.rubyrt/.env` → env vars → CLI flags. `prompt_vars` deep-merges; other keys override.
3. **Changeset** (`lib/rubyrt/changeset.rb`) — Uses `Rugged` (libgit2) to produce the diff between two git refs.
4. **Reviewer** (`lib/rubyrt/reviewer.rb`) — Orchestrates concurrent file reviews via `Async` fibers.
5. **PromptBuilder** (`lib/rubyrt/prompt_builder.rb`) — Renders Mustache templates with config, skills, and aux files merged in.
6. **LlmClient** (`lib/rubyrt/llm_client.rb`) — Wraps `ruby_llm`; handles retries, timeouts, tool registration, structured output.
7. **IssueParser** (`lib/rubyrt/issue_parser.rb`) — Validates LLM JSON against `IssueSchema`; converts `RawIssue` → `Issue`.
8. **PostProcessor** (`lib/rubyrt/post_processor.rb`) — Filters by `max_confidence`/`max_severity` before the critic pass.
9. **CodeEnricher** (`lib/rubyrt/code_enricher.rb`) — Attaches the actual affected code snippet to each issue.
10. **Verifier** (`lib/rubyrt/verifier.rb`) — Critic pass: re-examines each finding with an adversarial LLM call. Fails open (broken verdict keeps the finding).
11. **ReportRenderer** (`lib/rubyrt/report_renderer.rb`) — Renders CLI or Markdown output.

GitHub integration (`lib/rubyrt/github/`): `Commenter` posts inline PR comments via Octokit; `Approver` handles auto-approval; `GraphQLClient` resolves stale threads (requires a user PAT, not `GITHUB_TOKEN`).

LSP integration (`lib/rubyrt/lsp/`): `Client` spawns an LSP server (e.g. `ruby-lsp`) for symbol lookup; `SymbolTool` exposes it as a `ruby_llm` tool so the LLM can verify method/class existence.

## Code Conventions

- **Severity** 1–4 and **confidence** 1–4: lower numbers = stricter/higher priority.
- Valid issue tags: `bug`, `security`, `performance`, `readability`, `maintainability`, `overcomplexity`, `language`, `architecture`, `compatibility`, `deprecation`, `anti-pattern`, `naming`, `code-style`.
- `pr` is explicitly allowed as a parameter name in `.rubocop.yml`.
- RuboCop limits: 65-line methods, 120-line classes, 120-char lines. Block length cop is disabled for specs and gemspec.
- RSpec uses `expect()` syntax with no monkey-patching. Tests mock LLM responses — no real API key required.
- Specs isolate from `~/.rubyrt/.env` to avoid developer environment leakage.
