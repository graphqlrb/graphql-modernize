# GQLM301 — Interpreter plugin

Safety: safe. Removes `use GraphQL::Execution::Interpreter`; Interpreter has
been the schema default since 1.12. Conditional, option-bearing, and block-based
uses, and uses with trailing comments, are preserved and reported as manual.
