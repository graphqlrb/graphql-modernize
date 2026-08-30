# GQLM301 — Interpreter plugin

Safety: safe. Removes `use GraphQL::Execution::Interpreter`; Interpreter has
been the schema default since 1.12. Conditional, option-bearing, and block-based
uses are preserved and reported as manual.
