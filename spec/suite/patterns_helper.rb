def match(pat, val)
  Atomy::Compiler.eval(
    Atomy::AST::Set.new(
      :left => Atomy::AST::Pattern.new(:pattern => pat),
      :right => Atomy::AST::Literal.new(:value => val)),
    Atomy::Module.new,
    Binding.setup(
      Rubinius::VariableScope.of_sender,
      Rubinius::CompiledMethod.of_sender,
      Rubinius::ConstantScope.of_sender))
end

def expr(str)
  Atomy::Parser.parse_node(str)
end

def pat(str)
  mod = Atomy::Module.new
  p = expr(str).to_pattern
  p.in_context(mod)
  p
end

PATTERN_TYPES = []
Atomy::Patterns.constants.each do |c|
  val = Atomy::Patterns.const_get(c)
  PATTERN_TYPES << val if val.is_a?(Atomy::Patterns::SentientPattern)
end

def random_symbol
  sprintf("s_%04x", rand(16 ** 4)).to_sym
end

module Atomy::Patterns
  class Pattern
    def self.arbitrary
      args = []

      children[:required].each do
        args << random_pattern
      end

      children[:many].each do
        val = []
        rand(5).times do
          val << random_pattern
        end
        args << val
      end

      attributes[:required].each do
        args << random_symbol
      end

      attributes[:many].each do
        val = []
        rand(5).times do
          val << random_symbol
        end
        args << val
      end

      children[:optional].each do
        if rand(2) == 0
          args << nil
        else
          args << random_pattern
        end
      end

      attributes[:optional].each do
        if rand(2) == 0
          args << nil
        else
          args << random_symbol
        end
      end

      new(*args)
    end
  end

  class Any
    def self.arbitrary
      new
    end
  end

  class Attribute
    def self.arbitrary
      new(random_symbol.to_node,
          random_symbol.to_node,
          rand(5).times.collect { random_symbol.to_node })
    end
  end

  class Match
    def self.arbitrary
      new([:nil, :false, :true, :self, rand(100)].sample)
    end
  end

  class QuasiQuote
    def self.arbitrary
      new(Atomy::AST::QuasiQuote.new(:expression => random_symbol.to_node))
    end
  end

  class Quote
    def self.arbitrary
      new(random_symbol.to_node)
    end
  end
end

def random_pattern
  PATTERN_TYPES.sample.arbitrary
end

def for_every_pattern
  10.times do
    PATTERN_TYPES.each do |cls|
      x = cls.arbitrary

      begin
        yield x
      rescue Exception
        puts "failed with #{x.inspect}"
        raise
      end
    end
  end
end
