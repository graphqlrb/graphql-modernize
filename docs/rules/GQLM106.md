# GQLM106 — `property:`

Safety: safe. Renames the removed field option `property:` to its class API
equivalent `method:` inside GraphQL object and interface definitions.
Calls with duplicate `property:` or an existing `method:` are reported for
manual resolution, as are calls containing dynamic keyword expansion
(`**options`).
