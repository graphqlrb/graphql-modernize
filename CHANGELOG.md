# Changelog

## Unreleased

- Convert self-contained legacy `resolve:` lambdas to resolver methods with an
  explicit unsafe opt-in and manual fallback for ambiguous code.
- Tighten suppression scoping, inherited schema detection, configuration
  validation, convergence reporting, and rewrite diagnostics.

## 0.1.0

- Add Prism/astel-based class context and transactional rule execution.
- Add safe, unsafe, and manual graphql-ruby migration rules.
- Add dry-run/write CLI, suppression comments, iterative convergence, worker
  processes, and text/diff/JSON/GitHub/SARIF reporters.
