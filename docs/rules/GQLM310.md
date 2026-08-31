# GQLM310 — empty Union selections

Safety: manual. GraphQL-Ruby 2.5.3 began migrating toward rejecting Union
fields without subselections. Set
`allow_legacy_invalid_empty_selections_on_union` deliberately while fixing
affected queries. An override of
`legacy_invalid_empty_selections_on_union_with_type` also counts as an explicit
migration policy. Conditional configuration calls do not count as an explicit
migration policy.
