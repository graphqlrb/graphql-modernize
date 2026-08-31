# Changelog

## Unreleased

- Stop safely on Git inspection failures and unsafe write targets, ignore
  receiver-shaped schema calls, and preserve chained type wrappers, dynamic
  keyword expansions, and duplicate legacy options for review.
- Keep safe rewrites out of methods, lambdas, and unrelated blocks; preserve
  constant evaluation, trailing comments, call arguments, and existing options.
- Detect Visibility requirements only from class-level `visible?` hooks.
- Correct all five legacy scalar mappings and ignore unknown `types.X` calls.
- Move existing Visibility setup below root types and exclude graphql-ruby's
  framework base classes from application migrations.
- Keep strict runs write-free on parse errors and make suppression, file glob,
  version, and conflict-retry boundaries fail safely.
- Place Visibility after root schema configuration for GraphQL-Ruby 2.6.3+.
- Preserve side effects in conditional or block-based removals and legacy
  resolver lambdas that cannot be converted safely.
- Reject unsafe output paths, invalid explicit inputs, and malformed
  rule-specific configuration.
- Convert self-contained legacy `resolve:` lambdas to resolver methods with an
  explicit unsafe opt-in and manual fallback for ambiguous code.
- Tighten suppression scoping, inherited schema detection, configuration
  validation, convergence reporting, and rewrite diagnostics.

## 0.1.0

- Add Prism/astel-based class context and transactional rule execution.
- Add safe, unsafe, and manual graphql-ruby migration rules.
- Add dry-run/write CLI, suppression comments, iterative convergence, worker
  processes, and text/diff/JSON/GitHub/SARIF reporters.
