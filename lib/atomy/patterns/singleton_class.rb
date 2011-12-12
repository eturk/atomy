module Atomy::Patterns
  class SingletonClass < Pattern
    attributes(:body)
    generate

    def construct(g)
      get(g)
      @body.construct(g)
      g.send :new, 1
    end

    def target(g)
      @body.compile(g)
      g.send :singleton_class, 0
    end

    def matches?(g)
      g.pop
      g.push_true
    end

    def wildcard?
      true
    end
  end
end
