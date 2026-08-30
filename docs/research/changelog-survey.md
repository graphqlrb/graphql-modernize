# graphql-ruby migration survey

Surveyed against graphql-ruby's `CHANGELOG.md` through 2.6.10 (2026-08-27),
the historical official upgrader, rubocop-graphql's cop list, and astel 0.2.0.

## Rules selected for the first releases

| Rule | Upstream boundary | Static | Correction | Safety |
|---|---:|---|---|---|
| GQLM101 `.define` DSL | deprecated 1.10 | yes | guidance only | manual |
| GQLM102 `resolve:` field option | removed 2.0.1 | yes | simple lambda to method | unsafe/manual fallback |
| GQLM103 `GraphQL::Function` | removed 2.0 | yes | superclass replacement | unsafe |
| GQLM104 `to_graphql` / `graphql_definition` | deprecated 1.13 | yes | guidance only | manual |
| GQLM105 `types.X` | class API migration | yes | remove `types.` | safe |
| GQLM106 `property:` | class API migration | yes | rename to `method:` | safe |
| GQLM107 `field:` / `function:` | removed 2.0.1 | yes | remove option | safe |
| GQLM108 `GraphQL::Query::Arguments` | removed 2.0 | yes | guidance only | manual |
| GQLM201 Relay mutation | class API migration | yes | superclass replacement | unsafe |
| GQLM205 load failure error | renamed 1.9.4 | yes | constant replacement | safe |
| GQLM301 Interpreter plugin | default since 1.12 | yes | remove line | safe |
| GQLM302 Analysis::AST plugin | default since 1.12 | yes | remove line | safe |
| GQLM303 Connections plugin | default since 1.12 | yes | remove line | safe |
| GQLM304 `error_bubbling(true)` | deprecated 2.2.7 | yes | guidance only | manual |
| GQLM305 bidirectional pagination setting | deprecated 1.13.10 | yes | remove line | safe |
| GQLM306 default nodes setting | deprecated 1.13.10 | yes | remove line | safe |
| GQLM307 custom `visible?` without visibility plugin | required since 2.4.0 | project scan | insert plugin | unsafe |
| GQLM308 possible type/reference keys | changed 2.3.5 | yes | guidance only | manual |
| GQLM310 empty Union selections | deprecated behavior 2.5.3 | schema scan | guidance only | manual |
| GQLM401 `required: true` | default since 1.13.0 | yes | remove option | safe, opt-in |
| GQLM402 `null: true` | default since 1.13.0 | yes | remove option | safe, opt-in |
| GQLM501 complexity cost mode | migration support 2.5.3 | schema scan | guidance only | manual |

The remaining catalog entries need application-specific intent or do not have a
single generally correct rewrite, so they are reported as manual guidance.

GraphQL-Ruby 2.6.3 requires `Schema::Visibility` to be attached after root type
configuration, so GQLM307 appends the plugin. GraphQL-Ruby 2.5.15 added the
type-aware `legacy_invalid_empty_selections_on_union_with_type` hook; GQLM310
recognizes either legacy-selection hook as an explicit policy.

## Existing tools

The removed official `GraphQL::Upgrader` targeted the `.define` to class API
migration. Its transforms mixed regular expressions with `parser` AST
processing and did not cover later 2.x deprecations.

rubocop-graphql has `LegacyDSL`, but no equivalents of graphql-ruby's bundled
`GraphQL/DefaultNullTrue` and `GraphQL/DefaultRequiredTrue` cops. GQLM401 and
GQLM402 therefore overlap graphql-ruby's bundled cops and remain disabled by
default. GQLM403 is omitted: graphql-ruby's `GraphQL/FieldTypeInBlock` enforces
the opposite shape for lazy loading, so an automatic normalization would be a
style conflict rather than a migration.

## astel findings

astel 0.2.0 provides every required write primitive: transactions, same-offset
insertions, parse validation, keyword/list editing, body insertion, comments,
and unified diff output. `NodePattern` handles the narrow node and field checks
used here, but its DSL has no list literal syntax for argument-list matching.
Rules therefore compile a broad call pattern once and use
`Rewriter#find_keyword_argument` for keyword details.

## Sources

- <https://github.com/rmosolgo/graphql-ruby/blob/master/CHANGELOG.md>
- <https://github.com/rmosolgo/graphql-ruby/issues/3056>
- <https://github.com/DmitryTsepelev/rubocop-graphql/tree/master/lib/rubocop/cop/graphql>
- <https://github.com/ydah/astel>
