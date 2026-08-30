# GQLM307 — Visibility plugin

Safety: unsafe. When a GraphQL type defines `visible?`, inserts
`use GraphQL::Schema::Visibility, migration_errors: true` after existing schema
configuration. Resolve migration errors before removing the option.
