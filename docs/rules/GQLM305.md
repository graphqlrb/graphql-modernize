# GQLM305 — bidirectional pagination

Safety: safe. Removes the obsolete
`GraphQL::Relay::ConnectionType.bidirectional_pagination` assignment,
which does not affect the current pagination implementation. Conditional
assignments and values that may have side effects are reported as manual.
Assignments nested in methods, blocks, or expressions and assignments with
trailing comments are also preserved for manual review.
