module Atomo::Patterns
  class Match < Pattern
    def initialize(x)
      @value = x
    end

    def target(g)
      case @value
      when :true
        g.push_const :TrueClass
      when :false
        g.push_const :FalseClass
      when :nil
        g.push_const :NilClass
      when :self
        g.push_self
        g.send :class, 0
      else
        g.push_const @value.class.name.to_sym
      end
    end

    def matches?(g)
      g.push @value
      g.send :==, 1
    end

    def construct(g)
      g.push_const :Atomo
      g.find_const :Patterns
      g.find_const :Match
      g.push_literal @value
      g.send :new, 1
    end
  end
end