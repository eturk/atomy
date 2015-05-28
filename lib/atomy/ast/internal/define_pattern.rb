module Atomy
  module AST
    class DefinePattern < Block
      include NodeLike
      extend SentientNode

      children :pattern, :body
      attributes :module_name

      def pattern_definer
        DefineMethod.new(
          :body => @body,
          :receiver => Block.new(
            :contents => [Primitive.new(:value => :self)]),
          :arguments => [
            Compose.new(
              :left => Word.new(:text => :node),
              :right => Block.new(:contents => [@pattern])),
            @module_name
          ],
          :name => :_pattern,
          :always_match => true)
      end

      def bytecode(g, mod)
        pos(g)

        g.state.scope.nest_scope self

        blk = new_generator(g, :pattern_definition)
        blk.push_state self

        pos(blk)

        pattern_definer.bytecode(blk, mod)
        blk.ret

        blk.close
        blk.pop_state

        g.create_block blk
        g.push_self
        g.push_rubinius
        g.find_const :ConstantScope
        g.push_cpath_top
        g.find_const :Atomy
        g.find_const :AST
        g.push_rubinius
        g.find_const :ConstantScope
        g.push_self
        g.send :new, 1
        g.send :new, 2
        g.push_false
        g.send :call_under, 3
      end
    end
  end
end
