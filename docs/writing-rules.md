# Writing rules

Rules inherit `GraphQL::Modernize::Rules::Base`, declare metadata once, and
compile their astel node pattern at class load time.

```ruby
class PropertyOption < Base
  rule id: "GQLM106", safety: :safe, summary: "property to method"
  node_pattern :call_node, "(call_node receiver: nil name: :field)"

  def on_match(node, _captures)
    return unless inside?(node, :object, :interface)

    arguments = keyword_arguments(node, :property)
    return unless arguments.one? && !dynamic_keyword_arguments?(node)

    argument = arguments.first

    add_offense(argument.location, message: "replace property") do |rw|
      rw.replace_keyword_key(argument, :method)
    end
  end
end
```

Use the narrowest NodePattern that astel supports, then inspect GraphQL-specific
details in Ruby. `add_offense` wraps corrections in an astel transaction.
Every non-trivial correction needs a test for output, parse validity,
idempotence, and an unrelated DSL false-positive case.
