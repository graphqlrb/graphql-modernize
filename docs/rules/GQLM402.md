# GQLM402 — redundant `null: true`

Safety: safe, disabled by default. Removes `null: true`, the field default
since 1.13. Enable this rule explicitly when the style-only diff is acceptable.
Calls containing dynamic keyword expansion (`**options`) are left unchanged
for manual resolution, as are duplicate `null:` options.
