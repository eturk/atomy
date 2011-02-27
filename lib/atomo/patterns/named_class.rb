module Atomo::Patterns
  class NamedClass < Pattern
    attr_reader :name

    def initialize(n)
      @name = n.to_sym
    end

    def ==(b)
      b.kind_of?(NamedClass) and \
      @name == b.name
    end

    def target(g)
      g.push_const :Object
    end

    def matches?(g)
      g.pop
      g.push_true
    end

    def deconstruct(g, locals = {})
      Rubinius::AST::ClassVariableAssignment.new(0, @name, nil).bytecode(g)
      g.pop
    end

    def local_names
      []
    end
  end
end