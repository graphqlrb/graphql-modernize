# GQLM102 — `resolve:` field option

Safety: unsafe. With `--unsafe`, a self-contained three-argument lambda is
moved to an instance resolver method and legacy `obj` / `ctx` references become
`object` / `context`. The generated method accepts and ignores extra keyword
arguments, matching a legacy proc that did not read `args`. Captured locals,
`args`, nested blocks, bare calls,
dynamic field names, and method-name collisions are reported as manual because
an automatic rewrite could change their meaning.
