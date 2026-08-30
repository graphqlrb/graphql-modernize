# Migration guide

## 1.13 to 2.x

1. Run `bundle exec graphql-modernize run` and review the proposed safe changes.
2. Apply them with `--write`, then run the application's tests.
3. Run GQLM102 separately with `--unsafe`; resolve its manual fallbacks and
   GQLM101, GQLM104, and GQLM108 before updating.
4. Apply each unsafe superclass or Relay migration separately with
   `--only RULE --unsafe --write` and test it.
5. Update graphql-ruby and rerun the tool with the target version.

## 2.3 to 2.6

1. Remove obsolete execution and pagination settings with the safe rules.
2. Review type-index consumers reported by GQLM308.
3. Run GQLM307 by itself. Keep `migration_errors: true` while comparing Warden
   and Visibility, then remove that option after the differences are resolved.
4. Decide the validation and complexity migration modes reported by GQLM310
   and GQLM501 before accepting the new behavior.

Always review `git diff`; the tool deliberately leaves application-specific
choices as manual offenses.
