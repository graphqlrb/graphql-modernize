# GQLM302 — Analysis::AST plugin

Safety: safe. Removes `use GraphQL::Analysis::AST`; AST analysis has been the
schema default since 1.12. Conditional, option-bearing, and block-based uses are
preserved and reported as manual.
