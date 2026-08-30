# GQLM104 — legacy definition conversion

Safety: manual. `to_graphql` and `graphql_definition` disappeared with legacy
definitions. Remove the call when its result is unused; otherwise migrate the
consumer to class-based schema members.
