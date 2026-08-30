# Rule index

| ID | Safety | Migration |
|---|---|---|
| [GQLM101](GQLM101.md) | manual | `.define` DSL |
| [GQLM102](GQLM102.md) | manual | `resolve:` option |
| [GQLM103](GQLM103.md) | unsafe | `GraphQL::Function` |
| [GQLM104](GQLM104.md) | manual | legacy definition calls |
| [GQLM105](GQLM105.md) | safe | `types.X` |
| [GQLM106](GQLM106.md) | safe | `property:` |
| [GQLM107](GQLM107.md) | safe | removed field options |
| [GQLM108](GQLM108.md) | manual | `Query::Arguments` |
| [GQLM201](GQLM201.md) | unsafe | Relay mutation |
| [GQLM202](GQLM202.md) | manual | connection type factory |
| [GQLM203](GQLM203.md) | unsafe | Relay node field |
| [GQLM204](GQLM204.md) | unsafe | base connection |
| [GQLM205](GQLM205.md) | safe | load failure error |
| [GQLM301](GQLM301.md) | safe | Interpreter plugin |
| [GQLM302](GQLM302.md) | safe | Analysis plugin |
| [GQLM303](GQLM303.md) | safe | Connections plugin |
| [GQLM304](GQLM304.md) | manual | error bubbling |
| [GQLM305](GQLM305.md) | safe | bidirectional pagination |
| [GQLM306](GQLM306.md) | safe | default nodes field |
| [GQLM307](GQLM307.md) | unsafe | Visibility plugin |
| [GQLM308](GQLM308.md) | manual | schema type indexes |
| [GQLM309](GQLM309.md) | manual | error handlers |
| [GQLM310](GQLM310.md) | manual | empty Union selections |
| [GQLM401](GQLM401.md) | safe, opt-in | redundant required |
| [GQLM402](GQLM402.md) | safe, opt-in | redundant null |
| [GQLM501](GQLM501.md) | manual | complexity mode |
| [GQLM502](GQLM502.md) | unsafe | page size settings |

GQLM403 is intentionally not provided because graphql-ruby's
`GraphQL/FieldTypeInBlock` cop owns that style decision. GQLM503 was folded
into the specific GQLM310 and GQLM501 diagnostics.
