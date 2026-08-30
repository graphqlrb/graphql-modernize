# GQLM308 — schema type index keys

Safety: manual. Since 2.3.5, `Schema.possible_types` and
`Schema.references_to` use type classes instead of GraphQL name strings as
keys. Use `transform_keys(&:graphql_name)` only where the old shape is needed.
