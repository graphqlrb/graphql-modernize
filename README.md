<h1 align="center">graphql-modernize</h1>

<p align="center">
  <strong>A safe, static codemod for migrating deprecated graphql-ruby APIs</strong>
</p>

<p align="center">
  <a href="https://github.com/ydah/graphql-modernize/actions/workflows/main.yml"><img src="https://github.com/ydah/graphql-modernize/actions/workflows/main.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/ruby-%3E%3D%203.3-ruby.svg" alt="Ruby 3.3 or newer">
  <img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License">
</p>

<p align="center">
  <a href="#features">Features</a> ·
  <a href="#installation">Installation</a> ·
  <a href="#quick-start">Quick Start</a> ·
  <a href="#configuration">Configuration</a> ·
  <a href="#how-it-works">How It Works</a> ·
  <a href="#documentation">Documentation</a>
</p>

---

`graphql-modernize` migrates deprecated graphql-ruby APIs without booting the
application. It parses Ruby with Prism through [astel](https://github.com/ydah/astel),
preserves formatting, validates every rewrite, and reports changes before
writing them.

## Features

- Static analysis with no application boot or `graphql` gem dependency
- Project-wide GraphQL class and inheritance detection
- Safe, unsafe, and manual migration rules
- Formatting-preserving, transactional rewrites
- Syntax validation after every correction
- Unified diff, JSON, GitHub Actions, and SARIF output
- Inline, range, and file-wide suppression directives
- Parallel file processing with deterministic results
- Git safety checks before writing files

## Installation

Until the first gem release, add the repository to your `Gemfile`:

```ruby
gem "graphql-modernize", github: "ydah/graphql-modernize"
```

Then install:

```bash
bundle install
```

### Requirements

- Ruby 3.3 or newer
- A Git repository for guarded `--write` operations

The tool reads graphql-ruby source code but does not depend on or boot the
`graphql` gem.

## Quick Start

Inspect the project and inferred versions:

```bash
bundle exec graphql-modernize doctor
```

Run a dry migration and review the diff:

```bash
bundle exec graphql-modernize run
```

Apply safe corrections:

```bash
bundle exec graphql-modernize run --write
git diff
bundle exec rspec
```

Unsafe corrections require an explicit opt-in and can be run one rule at a
time:

```bash
bundle exec graphql-modernize run --only GQLM307 --unsafe --write
```

Without `--force`, writes require a clean Git working tree. Every target must
be tracked, non-symlinked, and inside that working tree.

### Commands

| Command | Description |
|---------|-------------|
| `graphql-modernize run [PATHS...]` | Detect migrations and optionally rewrite files |
| `graphql-modernize list` | List available rules and safety levels |
| `graphql-modernize explain RULE_ID` | Show rule details and migration guidance |
| `graphql-modernize doctor` | Validate configuration and detected inputs |
| `graphql-modernize version` | Print the installed version |

## Configuration

Create `.graphql-modernize.yml` in the project root:

```yaml
from_version: "1.13"
target_version: "2.6"
ruby_version: "3.3"

include:
  - "app/graphql/**/*.rb"
  - "lib/graphql/**/*.rb"
exclude:
  - "app/graphql/legacy/**/*.rb"

base_classes:
  object: ["ApplicationObjectType"]
  resolver: ["ApplicationResolver"]
  schema: ["ApplicationSchema"]

rules:
  GQLM401:
    enabled: true
  GQLM307:
    migration_errors: true

apply_unsafe: false
require_suppression_reason: true
iterations: 3
```

| Option | Default | Description |
|--------|---------|-------------|
| `from_version` | `Gemfile.lock` | Current graphql-ruby version |
| `target_version` | `Gemfile.lock` | Target graphql-ruby version |
| `ruby_version` | Current parser default | Ruby syntax version passed to astel |
| `include` | GraphQL paths under `app/` and `lib/` | Ruby file patterns to inspect |
| `exclude` | `vendor/**/*`, `tmp/**/*` | Paths excluded from inspection |
| `base_classes` | `{}` | Application-specific GraphQL base classes |
| `rules` | `{}` | Per-rule enablement and options |
| `apply_unsafe` | `false` | Apply unsafe corrections |
| `require_suppression_reason` | `false` | Require a reason on suppression directives |
| `iterations` | `3` | Rewrite rounds before final convergence retries |

CLI options override configuration. GQLM401 and GQLM402 are disabled by
default because they can create large style-only diffs.

## Suppression Directives

Suppress a rule on one line:

```ruby
field :name, types.String # graphql-modernize:disable GQLM105 -- staged migration
```

Suppress a range:

```ruby
# graphql-modernize:disable GQLM401 -- keep explicit defaults here
argument :id, ID, required: true
argument :name, String, required: true
# graphql-modernize:enable GQLM401
```

Use `graphql-modernize:disable-file GQLM101 -- reason` near the top of a file
for file-wide suppression. Unused suppressions are reported as GQLM000.

## Output and Exit Status

```bash
graphql-modernize run --format json
graphql-modernize run --format github
graphql-modernize run --format sarif --out results.sarif
```

| Status | Meaning |
|--------|---------|
| `0` | No unresolved offenses remain |
| `1` | Manual or uncorrected offenses remain |
| `2` | Configuration, strict parse, or internal failure |

## How It Works

1. File discovery expands configured Ruby paths and exclusions.
2. Prism parses each file through astel without loading the application.
3. A project-wide class hierarchy identifies GraphQL types and schemas.
4. Rules register transactional edits against matching AST nodes.
5. astel applies edits and validates the rewritten Ruby syntax.
6. The CLI reports the result and writes only when `--write` is present.

## Documentation

- [Migration guide](docs/migration-guide.md)
- [Rule index](docs/rules/README.md)
- [Writing rules](docs/writing-rules.md)
- [graphql-ruby migration research](docs/research/changelog-survey.md)

## Development

```bash
bundle install
bundle exec rake
bundle exec rake build
```

## Contributing

Bug reports and pull requests are welcome at
<https://github.com/ydah/graphql-modernize>.

## License

Released under the [MIT License](LICENSE.txt).
