# GQLM307 — Visibility plugin

Safety: unsafe. When a GraphQL type defines the class method `visible?`, inserts
`use GraphQL::Schema::Visibility, migration_errors: true` after existing schema
configuration. Placement after root type configuration is required by
GraphQL-Ruby 2.6.3 and newer. Resolve migration errors before removing the
option. Existing one-line Visibility configuration is moved after root types;
conditional, block-based, or trailing-comment configuration is reported as
manual so its surrounding behavior and commentary are preserved. Conditional
plugin calls do not count as guaranteed configuration and prevent automatic
insertion until they are resolved.
