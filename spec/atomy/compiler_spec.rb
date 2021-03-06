require "spec_helper"

require "atomy/locals"
require "atomy/compiler"
require "atomy/module"


describe Atomy::Compiler do
  class SomeCode
    def bytecode(gen, mod)
      gen.push_int(42)
    end
  end

  let(:node) { ast("42") }

  let(:compile_module) do
    Atomy::Module.new do
      def expand(_)
        SomeCode.new
      end
    end
  end

  describe ".compile" do
    it "returns a CompiledCode" do
      expect(described_class.compile(node, compile_module)).to(
        be_a(Rubinius::CompiledCode))
    end

    it "has the file set to the module's file" do
      compile_module.file = :"some/file"
      code = described_class.compile(node, compile_module)
      expect(code.file).to eq(:"some/file")
    end

    it "pushes a locals state" do
      spec = self

      state_code = Class.new do
        attr_accessor :line

        define_method(:bytecode) do |gen, mod|
          spec.expect(gen.state).to spec.be
          spec.expect(gen.state.scope).to spec.be

          gen.push_nil
        end
      end

      state_module = Atomy::Module.new do
        define_method(:expand) do |_|
          state_code.new
        end
      end

      described_class.compile(node, state_module)
    end

    it "pushes the given locals state" do
      state = Class.new(Atomy::LocalState).new

      spec = self
      state_code = Class.new do
        attr_accessor :line

        define_method(:bytecode) do |gen, mod|
          spec.expect(gen.state.scope).to spec.eq(state)

          gen.push_nil
        end
      end

      state_module = Atomy::Module.new do
        define_method(:expand) do |_|
          state_code.new
        end
      end

      described_class.compile(node, state_module, state)
    end

    it "sets #local_count and #local_names properly" do
      state_code = Class.new do
        attr_accessor :line

        define_method(:bytecode) do |gen, mod|
          gen.push_nil
          gen.state.scope.new_local(:a).reference.set_bytecode(gen)
        end
      end

      state_module = Atomy::Module.new do
        define_method(:expand) do |_|
          state_code.new
        end
      end

      res = described_class.compile(node, state_module)

      expect(res.local_count).to eq(1)
      expect(res.local_names).to eq([:a].to_tuple)
    end
  end

  describe ".package" do
    it "returns a CompiledCode" do
      packaged = described_class.package(:foo) do |gen|
        gen.push_nil
      end

      expect(packaged).to(be_a(Rubinius::CompiledCode))
    end

    it "has the file set to the given file" do
      packaged = described_class.package(:"some/file") do |gen|
        gen.push_nil
      end

      expect(packaged.file).to eq(:"some/file")
    end

    it "pushes a locals state" do
      described_class.package(:"some/file") do |gen|
        expect(gen.state).to be
        expect(gen.state.scope).to be

        gen.push_nil
      end
    end

    it "pushes the given locals state" do
      state = Class.new(Atomy::LocalState).new

      described_class.package(:"some/file", 0, state) do |gen|
        expect(gen.state.scope).to eq(state)

        gen.push_nil
      end
    end

    it "sets #local_count and #local_names properly" do
      code = described_class.package(:"some/file") do |gen|
        expect(gen.state).to be
        expect(gen.state.scope).to be

        gen.push_nil
        gen.state.scope.new_local(:a).reference.set_bytecode(gen)
      end

      expect(code.local_count).to eq(1)
      expect(code.local_names).to eq([:a].to_tuple)
    end
  end

  describe ".generate" do
    it "returns a Generator" do
      generator = described_class.generate(:foo) do |gen|
        gen.push_nil
      end

      expect(generator).to(be_a(CodeTools::Generator))
    end

    it "has the file set to the module's file" do
      gen = described_class.generate(:"some/file") do |gen|
        gen.push_nil
      end

      expect(gen.file).to eq(:"some/file")
    end

    it "has the line set to the given line" do
      gen = described_class.generate(:"some/file", 42) do |gen|
        gen.push_nil
      end

      expect(gen.line).to eq(42)
    end

    it "pushes a locals state" do
      described_class.generate(:"some/file") do |gen|
        expect(gen.state).to be
        expect(gen.state.scope).to be

        gen.push_nil
      end
    end

    it "pushes the given locals state" do
      state = Class.new(Atomy::LocalState).new

      described_class.generate(:"some/file", 0, state) do |gen|
        expect(gen.state.scope).to eq(state)

        gen.push_nil
      end
    end

    it "sets #local_count and #local_names properly" do
      gen =
        described_class.generate(:"some/file") do |gen|
          gen.push_nil
          gen.state.scope.new_local(:a).reference.set_bytecode(gen)
        end

      expect(gen.local_count).to eq(1)
      expect(gen.local_names).to eq([:a])
    end
  end

  describe ".construct_block" do
    let(:code) do
      described_class.compile(node, compile_module)
    end

    it "creates a BlockEnvironment from CompiledCode" do
      expect(described_class.construct_block(code, binding)).to(
        be_a(Rubinius::BlockEnvironment))
    end

    it "does not mutate the CompiledCode" do
      expect {
        described_class.construct_block(code, binding)
      }.to_not change { code.dup }
    end

    it "has the binding's variable scope for the block" do
      block = described_class.construct_block(code, binding)
      expect(block.scope).to eq(binding.variables)
    end

    it "sets the code's scope to the binding's constant scope" do
      block = described_class.construct_block(code, binding)
      expect(block.compiled_code.scope).to eq(binding.constant_scope)
    end

    it "sets the code's name to the binding's variable scope method name" do
      block = described_class.construct_block(code, binding)
      expect(block.compiled_code.name).to eq(binding.variables.method.name)
    end

    describe "determining the path" do
      class FileCode
        def bytecode(gen, mod)
          gen.push_scope
          gen.send :active_path, 0
        end
      end

      let(:compile_module) do
        Atomy::Module.new do
          def expand(_)
            FileCode.new
          end
        end
      end

      it "reflects the file path of the code" do
        code.file = :"foo/bar.rb"
        block = described_class.construct_block(code, binding)
        expect(block.call).to eq("foo/bar.rb")
      end
    end

    describe "binding access" do
      class IvarCode
        def initialize(name)
          @name = name
        end

        def bytecode(gen, mod)
          gen.push_ivar(:"@#{@name}")
        end
      end

      let(:compile_module) do
        Atomy::Module.new do
          def expand(node)
            if node.is_a?(Atomy::Grammar::AST::Prefix)
              if node.operator == :"@" && node.node.is_a?(Atomy::Grammar::AST::Word)
                return IvarCode.new(node.node.text)
              end
            end

            node
          end
        end
      end

      it "constructs the block with the given binding" do
        @bind = :outer_ivar

        class Foo
          def make_binding
            @bind = :bound_ivar
            binding
          end

          def mutate!
            @bind = :mutated_ivar
          end
        end

        foo = Foo.new
        bnd = foo.make_binding

        node = ast("@bind")
        code = described_class.compile(node, compile_module)
        block = described_class.construct_block(code, bnd)

        expect(block.call).to eq(:bound_ivar)

        foo.mutate!

        expect(block.call).to eq(:mutated_ivar)
      end
    end
  end
end
