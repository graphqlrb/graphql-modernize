# GQLM501 — complexity cost mode

Safety: manual. GraphQL-Ruby 2.5.3 added migration support for corrected
complexity merging. Set `complexity_cost_calculation_mode` explicitly, compare
limits, then adopt the corrected behavior. Conditional configuration calls do
not count as an explicit migration policy.
