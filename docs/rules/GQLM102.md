# GQLM102 — `resolve:` field option

Safety: manual. Move the proc body to an instance resolver method. Translate
legacy `obj` and `ctx` parameters to `object` and `context`, and check captured
local variables before removing the option.
