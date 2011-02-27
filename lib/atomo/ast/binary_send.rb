base = File.expand_path "../../", __FILE__

require base + '/patterns'

module Atomo
  module AST
    class BinarySend < Node
      attr_reader :operator, :lhs, :rhs, :private

      Atomo::Parser.register self

      def self.rule_name
        "binary_send"
      end

      def initialize(operator, lhs, rhs, privat = false)
        @operator = operator
        @lhs = lhs
        @rhs = rhs
        @private = privat
        @line = 1 # TODO
      end

      def ==(b)
        b.kind_of?(BinarySend) and \
        @operator == b.operator and \
        @lhs == b.lhs and \
        @rhs == b.rhs and \
        @private == b.private
      end

      def recursively(stop = nil, &f)
        return f.call self if stop and stop.call(self)

        f.call BinarySend.new(
          @operator,
          @lhs.recursively(stop, &f),
          @rhs.recursively(stop, &f),
          @private
        )
      end

      def construct(g, d)
        get(g)
        g.push_literal @operator
        @lhs.construct(g, d)
        @rhs.construct(g, d)
        g.push_literal @private
        g.send :new, 4
      end

      def self.grammar(g)
        g.binary_send =
          g.seq(
            :binary_send, :sig_sp, :operator, :sig_sp, :expression
          ) do |l, _, o, _, r|
            BinarySend.new(o,l,r)
          end | g.seq(
            :level3, :sig_sp, :operator, :sig_sp, :expression
          ) do |l, _, o, _, r|
            BinarySend.new(o,l,r)
          end | g.seq(
            :operator, :sig_sp, :expression
          ) do |o, _, r|
            BinarySend.new(o, Primitive.new(:self), r, true)
          end
      end

      def register_macro(body)
        Atomo::Macro.register(
          @operator,
          [@lhs, @rhs].collect do |n|
            Atomo::Macro.macro_pattern n
          end,
          body
        )
      end

      def bytecode(g)
        pos(g)
        @lhs.bytecode(g)
        @rhs.bytecode(g)
        g.send @operator.to_sym, 1, @private
      end
    end
  end
end
