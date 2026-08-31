# GQLM105 — `types.X`

Safety: safe. Rewrites the five legacy `TypeDefiner` scalars: `String` and
`Float` keep their Ruby classes, `Int` becomes `Integer`, and `Boolean` / `ID`
become `GraphQL::Types::Boolean` / `GraphQL::Types::ID`. Other `types.X` calls
and calls with arguments or blocks are left unchanged. Chained wrappers such as
`types.String.to_non_null_type` are reported for manual class-API migration.
