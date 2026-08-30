# GQLM305 — bidirectional pagination

Safety: safe. Removes the obsolete
`GraphQL::Relay::ConnectionType.bidirectional_pagination` assignment,
which does not affect the current pagination implementation. Conditional
assignments and values that may have side effects are reported as manual.
