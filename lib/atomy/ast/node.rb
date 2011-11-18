module Atomy
  module AST
    module SentientNode
      # hash from attribute to the type of child node it is
      # :normal = normal, required subnode
      # :many = a list of subnodes
      # :optional = optional (might be nil)
      def reset_children
        @@children = {
          :required => [],
          :many => [],
          :optional => []
        }
      end

      def reset_attributes
        @@attributes = {
          :required => [],
          :many => [],
          :optional => []
        }
      end

      def reset_slots
        @@slots = {
          :required => [],
          :many => [],
          :optional => []
        }
      end

      def inherited(sub)
        sub.reset_children
        sub.reset_attributes
        sub.reset_slots
      end

      def self.extended(sub)
        sub.reset_children
        sub.reset_attributes
        sub.reset_slots
      end

      def spec(into, specs)
        specs.each do |s|
          if s.respond_to?(:[]) and s.respond_to?(:size)
            if s.size == 2
              into[:optional] << s
            else
              into[:many] << s[0]
            end
          elsif s.to_s[-1] == ??
            into[:optional] << [s.to_s[0..-2].to_sym, "nil"]
          else
            into[:required] << s
          end
        end
      end

      def attributes(*specs)
        spec(@@attributes, specs)
      end

      def slots(*specs)
        spec(@@slots, specs)
      end

      def children(*specs)
        spec(@@children, specs)
      end

      def many_construct(n)
        x = <<END

          spliced = false
          size = 0
          @#{n}.each do |e|
            if e.kind_of?(::Atomy::AST::Splice) && d == 1
              if size > 0
                g.make_array size
              end
              e.construct(g, d)
              g.send :+, 1 if size > 0 || spliced
              spliced = true
              size = 0
            else
              e.construct(g, d)
              size += 1
            end
          end

          g.make_array size

          g.send :+, 1 if spliced
END
        x
      end

      def generate
        all = []
        args = ""
        (@@children[:required] + @@children[:many] +
         @@attributes[:required] + @@attributes[:many] +
         @@slots[:required] + @@slots[:many]).each do |x|
          all << x.to_s
          args << ", #{x}_"
        end

        lists = @@children[:many] + @@attributes[:many] + @@slots[:many]

        (@@children[:optional] + @@attributes[:optional]).each do |x, d|
          all << x.to_s
          args << ", #{x}_ = #{d}"
        end

        non_slots = all.dup
        @@slots[:optional].each do |x, d|
          all << x.to_s
          args << ", #{x}_ = #{d}"
        end

        class_eval <<EOF
          attr_accessor :line#{all.collect { |a| ", :#{a}" }.join}
EOF

        class_eval <<EOF
          def initialize(line#{args})
            raise "initialized with non-integer `line': \#{line}" unless line.is_a?(Integer)
            #{@@children[:required].collect { |n| "raise \"initialized with non-node `#{n}': \#{#{n}_.inspect}\" unless #{n}_ and #{n}_.is_a?(NodeLike)" }.join("; ")}
            #{@@children[:many].collect { |n| "raise \"initialized with non-homogenous list `#{n}': \#{#{n}_.inspect}\" unless #{n}_.all? { |x| x.is_a?(NodeLike) }" }.join("; ")}
            #{@@children[:optional].collect { |n, _| "raise \"initialized with non-node `#{n}': \#{#{n}_.inspect}\" unless #{n}_.nil? or #{n}_.is_a?(NodeLike)" }.join("; ")}
            #{@@attributes[:required].collect { |a| "raise \"initialized without `#{a}': \#{self.inspect}\" if #{a}_.nil?" }.join("; ")}
            #{@@slots[:required].collect { |s| "raise \"initialized without `#{s}': \#{#{s}_.inspect}\" if #{s}_.nil?" }.join("; ")}

            @line = line
            #{all.collect { |a| "@#{a} = #{a}_" }.join("; ")}
          end
EOF

        class_eval <<EOF
          def construct(g, d = nil)
            get(g)
            g.push_int(@line)

            #{@@children[:required].collect { |n|
                "@#{n}.construct(g, d)"
              }.join("; ")}

            #{@@children[:many].collect { |n|
                many_construct(n)
              }.join("; ")}

            #{@@attributes[:required].collect { |a|
                "g.push_literal(@#{a})"
              }.join("; ")}

            #{@@attributes[:many].collect { |a|
                "@#{a}.each { |n| g.push_literal n }; g.make_array @#{a}.size"
              }.join("; ")}

            #{@@slots[:required].collect { |a|
                "g.push_literal(@#{a})"
              }.join("; ")}

            #{@@slots[:many].collect { |a|
                "@#{a}.each { |n| g.push_literal n }; g.make_array @#{a}.size"
              }.join("; ")}

            #{@@children[:optional].collect { |n, _|
                "if @#{n}; @#{n}.construct(g, d); else; g.push_nil; end"
              }.join("; ")}

            #{@@attributes[:optional].collect { |a, _|
                "g.push_literal(@#{a})"
              }.join("; ")}

            #{@@slots[:optional].collect { |a, _|
                "g.push_literal(@#{a})"
              }.join("; ")}

            g.send :new, #{all.size + 1}
          end
EOF

        class_eval <<EOF
          def eql?(b)
            b.kind_of?(#{self.name}) \\
            #{non_slots.collect { |a| " and @#{a}.eql?(b.#{a})" }.join}
          end

          alias :== :eql?
EOF

        req_cs =
          @@children[:required].collect { |n|
            ", @#{n}.recursively(pre, post, :#{n}, &f)"
          }.join

        many_cs =
          @@children[:many].collect { |n|
            ", @#{n}.zip((0 .. @#{n}.size - 1).to_a).collect { |n, i| n.recursively(pre, post, [:#{n}, i], &f) }"
          }.join

        opt_cs =
          @@children[:optional].collect { |n, _|
            ", @#{n} ? @#{n}.recursively(pre, post, :#{n}, &f) : nil"
          }.join

        req_as =
          (@@attributes[:required] + @@attributes[:many]).collect { |a|
            ", @#{a}"
          }.join

        opt_as = @@attributes[:optional].collect { |a, _|
            ", @#{a}"
          }.join

        req_ss =
          (@@slots[:required] + @@slots[:many]).collect { |a|
            ", @#{a}"
          }.join

        opt_ss = @@slots[:optional].collect { |a, _|
            ", @#{a}"
          }.join

        class_eval <<EOF
          def recursively(pre = nil, post = nil, context = nil, &f)
            if pre and pre.arity == 2
              stop = pre.call(self, context)
            elsif pre
              stop = pre.call(self)
            else
              stop = false
            end

            if stop
              if f.arity == 2
                res = f.call(self, context)
                post.call(context) if post
                return res
              else
                res = f.call(self)
                post.call(context) if post
                return res
              end
            end

            recursed = #{self.name}.new(
              @line#{req_cs + many_cs + req_as + req_ss + opt_cs + opt_as + opt_ss}
            )

            if f.arity == 2
              res = f.call(recursed, context)
            else
              res = f.call(recursed)
            end

            post.call(context) if post

            res
          end
EOF

        creq_cs =
          @@children[:required].collect { |n|
            ", f.call(@#{n})"
          }.join

        cmany_cs =
          @@children[:many].collect { |n|
            ", @#{n}.each.collect { |n| f.call(n) }"
          }.join

        copt_cs =
          @@children[:optional].collect { |n, _|
            ", @#{n} ? f.call(@#{n}) : nil"
          }.join

        all =
          (@@children[:required] +
            @@children[:many] +
            @@children[:optional]).collect { |n, _| "@#{n}" }

        class_eval <<EOF
          def children(&f)
            if block_given?
              #{self.name}.new(
                @line#{creq_cs + cmany_cs + req_as + req_ss + copt_cs + opt_as + opt_ss}
              )
            else
              [#{all.join(", ")}]
            end
          end
EOF

        class_eval <<EOF
          def walk_with(b, stop = nil, &f)
            f.call(self, b)

            return if !b.is_a?(#{self.name}) || (stop && stop.call(self, b))

            children.zip(b.children).each do |x, y|
              if x.respond_to?(:zip)
                x.zip(y).each do |x2, y2|
                  if x2
                    x2.walk_with(y2, stop, &f)
                  elsif y2
                    f.call(x2, y2)
                  end
                end
              elsif x
                x.walk_with(y, stop, &f)
              elsif y
                # x is nil, y is not
                f.call(x, y)
              end
            end
          end
EOF

        class_eval <<EOF
          def bottom?
            #{@@children.values.flatten(1).empty?.inspect}
          end
EOF

        attrs =
          @@attributes[:required] + @@attributes[:many] +
            @@attributes[:optional].collect(&:first)

        class_eval <<EOF
          def details
            #{attrs.inspect}
          end
EOF

        slots =
          @@slots[:required] + @@slots[:many] +
            @@slots[:optional].collect(&:first)

        class_eval <<EOF
          def slots
            #{slots.inspect}
          end
EOF

        required = @@children[:required].collect { |c| ", [:\"#{c}\", @#{c}.to_sexp]" }.join
        many = @@children[:many].collect { |c| ", [:\"#{c}\", @#{c}.collect(&:to_sexp)]" }.join
        optional = @@children[:optional].collect { |c, _| ", [:\"#{c}\", @#{c} && @#{c}.to_sexp]" }.join

        a_required = @@attributes[:required].collect { |c| ", [:\"#{c}\", @#{c}]" }.join
        a_many = @@attributes[:many].collect { |c| ", [:\"#{c}\", @#{c}]" }.join
        a_optional = @@attributes[:optional].collect { |c, _| ", [:\"#{c}\", @#{c}]" }.join

        s_required = @@slots[:required].collect { |c| ", [:\"#{c}\", @#{c}]" }.join
        s_many = @@slots[:many].collect { |c| ", [:\"#{c}\", @#{c}]" }.join
        s_optional = @@slots[:optional].collect { |c, _| ", [:\"#{c}\", @#{c}]" }.join

        class_eval <<EOF
          def to_sexp
            [:"#{self.name.split("::").last.downcase}"#{required}#{many}#{optional}#{a_required}#{a_many}#{a_optional}#{s_required}#{s_many}#{s_optional}]
          end
EOF

      end
    end

    module NodeLike
      attr_accessor :line

      def through_quotes(pre_ = nil, post_ = nil, &f)
        depth = 0

        pre = proc { |x, c|
          (pre_ && pre_.call(*([x, c, depth][0, pre_.arity])) && depth == 0) || \
            x.kind_of?(AST::QuasiQuote) || \
            x.unquote?
        }

        rpre = proc { |x, c|
          pre_ && pre_.call(*([x, c, 0][0, pre_.arity]))
        }

        post = proc { post_ && post_.call }

        action = proc { |e, c|
          if e.unquote?
            depth -= 1
            if depth == 0
              depth += 1
              u = e.expression.recursively(rpre, post_, :unquoted, &f)
              next e.class.new(
                e.line,
                u
              )
            end

            u = e.expression.recursively(pre, post, :expression, &action)
            depth += 1
            e.class.new(
              e.line,
              u
            )
          elsif e.kind_of?(Atomy::AST::QuasiQuote)
            depth += 1
            q = e.expression.recursively(pre, post, :expression, &action)
            depth -= 1
            Atomy::AST::QuasiQuote.new(
              e.line,
              q
            )
          else
            if depth == 0
              f.call(e)
            else
              e
            end
          end
        }

        recursively(pre, post, &action)
      end

      def unquote(d)
        return unless d
        d - 1
      end

      def quote(d)
        return unless d
        d + 1
      end

      def get(g)
        g.push_cpath_top
        self.class.name.split("::").each do |n|
          g.find_const n.to_sym
        end
      end

      def to_node
        self
      end

      def message_name
        nil
      end

      def unquote?
        false
      end

      def caller
        Send.new(
          @line,
          self,
          [],
          "call"
        )
      end

      def evaluate(bnd = nil, *args)
        if bnd.nil?
          bnd = Binding.setup(
            Rubinius::VariableScope.of_sender,
            Rubinius::CompiledMethod.of_sender,
            Rubinius::StaticScope.of_sender
          )
        end

        Atomy::Compiler.evaluate_node(self, bnd, *args)
      end

      # this is overridden by macro definitions
      def _expand
        self
      end

      def do_expand
        _expand.to_node
      end

      def msg_expand
        return do_expand unless macro_name and respond_to?(macro_name)
        send(macro_name)
      rescue MethodFail
        do_expand
      end

      def expand
        if lets = Atomy::Macro::Environment.let[self.class]
          x = self
          lets.reverse_each do |l|
            begin
              x = x.send(l)
              return x.expand unless x.kind_of?(self.class)
            rescue MethodFail
            end
          end
          x.msg_expand.to_node
        else
          msg_expand.to_node
        end
      rescue
        if respond_to?(:show)
          $stderr.puts "while expanding #{show}"
        else
          $stderr.puts "while expanding a #{to_sexp.inspect}"
        end

        raise
      end

      alias :prepare :expand

      def define_macro(body, file = :macro)
        pattern = macro_pattern

        unless macro_name
          @@stats ||= {}
          @@stats[self.class] ||= []
          @@stats[self.class] << self

          Atomy::Macro.register(
            self.class,
            pattern,
            body,
            Atomy::CodeLoader.compiling
          )

          return
        end

        Atomy::AST::Define.new(
          0,
          Atomy::AST::Compose.new(
            0,
            pattern.quoted,
            Atomy::AST::Word.new(0, macro_name.to_s)
          ),
          Atomy::AST::Send.new(
            body.line,
            Atomy::AST::Send.new(
              body.line,
              body,
              [],
              "to_node"
            ),
            [],
            "expand"
          )
        ).evaluate(
          Binding.setup(
            Rubinius::VariableScope.of_sender,
            Rubinius::CompiledMethod.of_sender,
            Rubinius::StaticScope.new(Atomy::AST)
          ), nil, file.to_s, pattern.quoted.line
        )
      end

      def macro_name
        nil
      end

      def compile(g)
        prepare.bytecode(g)
      end

      def load_bytecode(g)
        compile(g)
      end

      def to_pattern
        pattern
      end

      def macro_pattern
        Atomy::Patterns::QuasiQuote.new(
          Atomy::AST::QuasiQuote.new(
            @line,
            self
          )
        )
      end
    end

    class Node < Rubinius::AST::Node
      include Atomy::Macro::Helpers
      include NodeLike
      extend SentientNode

      def bytecode(g)
        raise "no #bytecode for #{self.class.name}"
      end
    end

    class Tree < Node
      children [:nodes]
      generate

      def bytecode(g)
        @nodes.each { |n| n.compile(g) }
      end

      def collect
        Tree.new(0, @nodes.collect { |n| yield n })
      end
    end

    class Script < Rubinius::AST::Container
      def initialize(body)
        super body
        @name = :__script__
      end

      def sprinkle_salt(g, by)
        skip_salt = g.new_label

        g.push_cpath_top
        g.find_const :Atomy
        g.find_const :CodeLoader
        g.send :compiled?, 0
        g.git skip_salt

        g.push_cpath_top
        g.find_const :Atomy
        g.find_const :Macro
        g.find_const :Environment
        g.push by
        g.send :salt!, 1
        g.pop

        skip_salt.set!
      end

      def bytecode(g)
        super(g)

        container_bytecode(g) do
          g.push_state self

          when_load = g.new_label
          done_loading = g.new_label
          when_run = g.new_label
          start = g.new_label
          done = g.new_label

          g.push_cpath_top
          g.find_const :Atomy
          g.find_const :CodeLoader
          g.send :reason, 0
          g.push_literal :load
          g.send :==, 1
          g.git when_load

          done_loading.set!

          g.push_cpath_top
          g.find_const :Atomy
          g.find_const :CodeLoader
          g.send :reason, 0
          g.push_literal :run
          g.send :==, 1
          g.git when_run

          before = Atomy::Macro::Environment.salt

          start.set!
          @body.bytecode g

          after = Atomy::Macro::Environment.salt
          g.goto done

          when_load.set!

          sprinkle_salt(g, after - before) if after > before

          Atomy::CodeLoader.when_load.each do |e, c|
            if c
              skip = g.new_label

              g.push_cpath_top
              g.find_const :Atomy
              g.find_const :CodeLoader
              g.send :compiled?, 0
              g.git skip

              e.load_bytecode(g)
              g.pop

              skip.set!
            else
              e.load_bytecode(g)
              g.pop
            end
          end
          g.goto done_loading

          when_run.set!

          sprinkle_salt(g, after - before) if after > before

          Atomy::CodeLoader.when_run.each do |e, c|
            if c
              skip = g.new_label

              g.push_cpath_top
              g.find_const :Atomy
              g.find_const :CodeLoader
              g.send :compiled?, 0
              g.git skip

              e.load_bytecode(g)
              g.pop

              skip.set!
            else
              e.load_bytecode(g)
              g.pop
            end
          end
          g.goto start

          done.set!
          g.ret
          g.pop_state
        end
      end
    end
  end
end

class Object
  def to_node
    raise "not a node: #{self.inspect}"
  end
end

class Integer
  def to_node
    Atomy::AST::Primitive.new -1, self
  end
end

class Float
  def to_node
    Atomy::AST::Literal.new -1, self
  end
end

class String
  def to_node
    Atomy::AST::String.new -1, self
  end
end

class Array
  def to_node
    Atomy::AST::List.new(-1, collect(&:to_node))
  end
end

class NilClass
  def to_node
    Atomy::AST::Primitive.new -1, :nil
  end
end

class Symbol
  def to_node
    Atomy::AST::Literal.new -1, self
  end
end
