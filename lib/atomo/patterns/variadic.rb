module Atomo::Patterns
  class Variadic < Pattern
    attr_accessor :pattern

    def initialize(p)
      @pattern = p
    end

    def target(g)
      g.push_const :Object
    end

    def matches?(g)
      g.pop
      g.push_true
    end

    def deconstruct(g, locals = {})
      singleton = g.new_label
      done = g.new_label

      g.dup
      g.push_const :Array
      g.swap
      g.instance_of
      g.git singleton

      g.cast_array
      g.goto done

      singleton.set!
      g.make_array 1

      done.set!
      @pattern.deconstruct(g, locals)
    end

    def construct(g)
      g.push_const :Atomo
      g.find_const :Patterns
      g.find_const :Variadic
      @pattern.construct(g)
      g.send :new, 1
    end

    def local_names
      @pattern.local_names
    end
  end
end
