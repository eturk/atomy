module Atomy::Patterns
  class BlockPass < Pattern
    children(:pattern)
    generate

    def target(g)
      g.push_const :Object
    end

    def matches?(g)
      g.pop
      g.push_true
    end

    def deconstruct(g, locals = {})
      match = g.new_label

      g.dup
      g.is_nil
      g.git match

      g.push_cpath_top
      g.find_const :Proc
      g.swap
      g.send :__from_block__, 1

      match.set!
      @pattern.deconstruct(g, locals)
    end

    def wildcard?
      @pattern.wildcard?
    end
  end
end
