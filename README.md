# graphql-modernize

`graphql-modernize` migrates deprecated graphql-ruby APIs without booting the
application. It parses Ruby with Prism through [astel](https://github.com/ydah/astel),
preserves formatting, validates every rewrite, and reports changes before writing.

## Installation

```bash
bundle add graphql-modernize
```

Ruby 3.3 or newer is required. The tool does not depend on the `graphql` gem.

## Quick start

Start with a dry run:

```bash
bundle exec graphql-modernize run
```

Review the unified diff, then apply safe rules:

```bash
bundle exec graphql-modernize run --write
git diff
bundle exec rspec
```

Without `--force`, writes require a clean Git working tree and every target
must be a tracked, non-symlinked path inside that working tree.

Unsafe rules require an explicit opt-in and can be run one at a time:

```bash
bundle exec graphql-modernize run --only GQLM307 --unsafe --write
```

Useful commands:

```text
graphql-modernize list
graphql-modernize explain GQLM307
graphql-modernize doctor
graphql-modernize run --format json
graphql-modernize run --format github
graphql-modernize run --format sarif --out results.sarif
```

Exit status is `0` when no unresolved offenses remain, `1` when manual or
unfixed offenses remain, and `2` for configuration, parse (`--strict`), or
internal errors.

## Configuration

Create `.graphql-modernize.yml` in the project root:

```yaml
from_version: "1.13"
target_version: "2.6"
ruby_version: "3.3"
include: ["app/graphql/**/*.rb", "lib/graphql/**/*.rb"]
exclude: ["app/graphql/legacy/**/*.rb"]
base_classes:
  object: ["ApplicationObjectType"]
rules:
  GQLM401:
    enabled: true
  GQLM307:
    migration_errors: true
apply_unsafe: false
require_suppression_reason: true
```

CLI options override configuration. GQLM401 and GQLM402 are disabled by
default because they can create large style-only diffs.

## Suppression comments

```ruby
field :name, types.String # graphql-modernize:disable GQLM105 -- staged migration

# graphql-modernize:disable GQLM401 -- keep explicit defaults here
argument :id, ID, required: true
# graphql-modernize:enable GQLM401
```

Use `graphql-modernize:disable-file GQLM101 -- reason` near the top of a file
for file-wide suppression. Unused suppressions are reported as GQLM000.

See [the migration guide](docs/migration-guide.md), [rule index](docs/rules/README.md),
and [rule authoring guide](docs/writing-rules.md).

## Development

Run `bundle install`, then `bundle exec rake`. Build the gem with
`bundle exec rake build`.

## Contributing

Bug reports and pull requests are welcome at <https://github.com/ydah/graphql-modernize>.

## License

The gem is available under the [MIT License](LICENSE.txt).
