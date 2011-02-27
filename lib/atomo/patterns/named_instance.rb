module Atomo::Patterns
  class NamedInstance < Pattern
    attr_reader :name

    def initialize(n)
      @name = n.to_sym
    end

    def ==(b)
      b.kind_of?(NamedInstance) and \
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
      Rubinius::AST::InstanceVariableAssignment.new(0, @name, nil).bytecode(g)
      g.pop
    end

    def local_names
      []
    end
  end
end