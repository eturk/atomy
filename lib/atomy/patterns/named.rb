module Atomy::Patterns
  class Named < Pattern
    children(:pattern)
    attributes(:name)
    generate

    def match(g, set = false, locals = {})
      if @pattern.is_a?(Any)
        deconstruct(g, locals)
      else
        super
      end
    end

    def target(g)
      @pattern.target(g)
    end

    def matches?(g)
      @pattern.matches?(g)
    end

    def deconstruct(g, locals = {})
      if locals[@name]
        local = locals[@name]
      else
        local = Atomy.assign_local(g, @name)
      end

      if @pattern.bindings > 0
        g.dup
        @pattern.deconstruct(g, locals)
      end

      local.set_bytecode(g)
      g.pop
    end

    def names
      [@name]
    end

    def bound
      1
    end

    def wildcard?
      @pattern.wildcard?
    end

    def matches_self?
      @pattern.matches_self?
    end
  end
end
