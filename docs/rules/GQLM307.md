# GQLM307 — Visibility plugin

Safety: unsafe. When a GraphQL type defines `visible?`, inserts
`use GraphQL::Schema::Visibility, migration_errors: true` after existing schema
configuration. Placement after root type configuration is required by
GraphQL-Ruby 2.6.3 and newer. Resolve migration errors before removing the
option.
