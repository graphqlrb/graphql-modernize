# GQLM306 — default nodes field

Safety: safe. Removes the obsolete
`GraphQL::Relay::ConnectionType.default_nodes_field` assignment, which
does not affect the current pagination implementation. Conditional assignments
and values that may have side effects are reported as manual.
Assignments nested in methods, blocks, or expressions and assignments with
trailing comments are also preserved for manual review.
