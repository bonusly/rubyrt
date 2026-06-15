# RubyRT: Ruby (but mostly Rails) Review Thing

RubyRT is an opinionated but helpful and flexible AI code review tool for Ruby and Rails projects. It is heavily inspired by [Gito](https://github.com/Nayjest/Gito) and brings the same LLM-driven review workflow to Ruby codebases, with extra knowledge of Ruby-specific tooling such as RuboCop, Brakeman, Solargraph, and the Ruby LSP.

## Features

- AI-powered code review via any OpenAI-compatible LLM (powered by [ruby_llm](https://github.com/crmne/ruby_llm)).
- Ruby and Rails-aware review prompts out of the box.
- Reads project skills and rules from `.agents`, `.claude`, and `.cursor` directories.
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
          model: gpt-4o
```

## Development

```bash
bundle install
bundle exec rake
```

## License

MIT. See [LICENSE.txt](LICENSE.txt).
