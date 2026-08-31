# GQLM107 — removed field options

Safety: safe. Removes `field:` and `function:` from field definitions. They
were already no-ops before GraphQL-Ruby removed them in 2.0.1. Values that may
have side effects are preserved and reported as manual. String-keyed hashes are
not treated as legacy keyword options.
