require "spec_helper"

require "atomy/message_structure"
require "atomy/node/equality"

describe Atomy::MessageStructure do
  subject { described_class.new(node) }

  context "when not a message-like structure" do
    let(:node) { ast("42") }

    describe "#name" do
      it "raises UnknownMessageStructure" do
        expect { subject.name }.to raise_error(described_class::UnknownMessageStructure)
      end
    end

    its(:arguments) { should be_empty }
    its(:receiver) { should be_nil }
    its(:proc_argument) { should be_nil }
    its(:block) { should be_nil }
    its(:splat_argument) { should be_nil }
  end

  context "when a word" do
    let(:node) { ast("foo") }
    its(:name) { should == :foo }
    its(:arguments) { should be_empty }
    its(:receiver) { should be_nil }
    its(:proc_argument) { should be_nil }
    its(:block) { should be_nil }
    its(:splat_argument) { should be_nil }
  end

  context "when a word followed by !" do
    let(:node) { ast("foo!") }
    its(:name) { should == :foo! }
    its(:arguments) { should be_empty }
    its(:receiver) { should be_nil }
    its(:proc_argument) { should be_nil }
    its(:block) { should be_nil }
    its(:splat_argument) { should be_nil }
  end

  context "when a word followed by ?" do
    let(:node) { ast("foo?") }
    its(:name) { should == :foo? }
    its(:arguments) { should be_empty }
    its(:receiver) { should be_nil }
    its(:proc_argument) { should be_nil }
    its(:block) { should be_nil }
    its(:splat_argument) { should be_nil }
  end

  context "when a word followed by some other symbol" do
    let(:node) { ast("foo.") }

    describe "#name" do
      it "raises UnknownMessageStructure" do
        expect { subject.name }.to raise_error(described_class::UnknownMessageStructure)
      end
    end

    its(:arguments) { should be_empty }
    its(:receiver) { should be_nil }
    its(:proc_argument) { should be_nil }
    its(:block) { should be_nil }
    its(:splat_argument) { should be_nil }
  end

  context "when a word with arguments" do
    let(:node) { ast("foo(a, b)") }
    its(:name) { should == :foo }
    its(:arguments) { should == [ast("a"), ast("b")] }
    its(:receiver) { should be_nil }
    its(:proc_argument) { should be_nil }
    its(:block) { should be_nil }
    its(:splat_argument) { should be_nil }
  end

  context "when a word with arguments with a splat" do
    let(:node) { ast("foo(a, b, *c)") }
    its(:name) { should == :foo }
    its(:arguments) { should == [ast("a"), ast("b")] }
    its(:receiver) { should be_nil }
    its(:proc_argument) { should be_nil }
    its(:block) { should be_nil }
    its(:splat_argument) { should == ast("c") }
  end

  context "when a word followed by ! with arguments" do
    let(:node) { ast("foo!(a, b)") }
    its(:name) { should == :foo! }
    its(:arguments) { should == [ast("a"), ast("b")] }
    its(:receiver) { should be_nil }
    its(:proc_argument) { should be_nil }
    its(:block) { should be_nil }
    its(:splat_argument) { should be_nil }
  end

  context "when a word followed by ? with arguments" do
    let(:node) { ast("foo?(a, b)") }
    its(:name) { should == :foo? }
    its(:arguments) { should == [ast("a"), ast("b")] }
    its(:receiver) { should be_nil }
    its(:proc_argument) { should be_nil }
    its(:block) { should be_nil }
    its(:splat_argument) { should be_nil }
  end

  context "when a word with a proc argument" do
    let(:node) { ast("foo &blk") }
    its(:name) { should == :foo }
    its(:arguments) { should be_empty }
    its(:receiver) { should be_nil }
    its(:proc_argument) { should == ast("blk") }
    its(:block) { should be_nil }
    its(:splat_argument) { should be_nil }
  end

  context "when a word followed by ! with a proc argument" do
    let(:node) { ast("foo! &blk") }
    its(:name) { should == :foo! }
    its(:arguments) { should be_empty }
    its(:receiver) { should be_nil }
    its(:proc_argument) { should == ast("blk") }
    its(:block) { should be_nil }
    its(:splat_argument) { should be_nil }
  end

  context "when a word followed by ? with a proc argument" do
    let(:node) { ast("foo? &blk") }
    its(:name) { should == :foo? }
    its(:arguments) { should be_empty }
    its(:receiver) { should be_nil }
    its(:proc_argument) { should == ast("blk") }
    its(:block) { should be_nil }
    its(:splat_argument) { should be_nil }
  end

  context "when a word with arguments with a proc argument" do
    let(:node) { ast("foo(a, b) &blk") }
    its(:name) { should == :foo }
    its(:arguments) { should == [ast("a"), ast("b")] }
    its(:receiver) { should be_nil }
    its(:proc_argument) { should == ast("blk") }
    its(:block) { should be_nil }
    its(:splat_argument) { should be_nil }
  end

  context "when a word followed by ! with arguments with a proc argument" do
    let(:node) { ast("foo!(a, b) &blk") }
    its(:name) { should == :foo! }
    its(:arguments) { should == [ast("a"), ast("b")] }
    its(:receiver) { should be_nil }
    its(:proc_argument) { should == ast("blk") }
    its(:block) { should be_nil }
    its(:splat_argument) { should be_nil }
  end

  context "when a word followed by ? with arguments with a proc argument" do
    let(:node) { ast("foo?(a, b) &blk") }
    its(:name) { should == :foo? }
    its(:arguments) { should == [ast("a"), ast("b")] }
    its(:receiver) { should be_nil }
    its(:proc_argument) { should == ast("blk") }
    its(:block) { should be_nil }
    its(:splat_argument) { should be_nil }
  end

  context "when a word with a block that has no arguments" do
    let(:node) { ast("foo: a + b") }
    its(:name) { should == :foo }
    its(:arguments) { should be_empty }
    its(:receiver) { should be_nil }
    its(:proc_argument) { should be_nil }
    its(:block) { should == ast("{ a + b }") }
    its(:splat_argument) { should be_nil }
  end

  context "when a word followed by ! with a block that has no arguments" do
    let(:node) { ast("foo!: a + b") }
    its(:name) { should == :foo! }
    its(:arguments) { should be_empty }
    its(:receiver) { should be_nil }
    its(:proc_argument) { should be_nil }
    its(:block) { should == ast("{ a + b }") }
    its(:splat_argument) { should be_nil }
  end

  context "when a word followed by ? with a block that has no arguments" do
    let(:node) { ast("foo?: a + b") }
    its(:name) { should == :foo? }
    its(:arguments) { should be_empty }
    its(:receiver) { should be_nil }
    its(:proc_argument) { should be_nil }
    its(:block) { should == ast("{ a + b }") }
    its(:splat_argument) { should be_nil }
  end

  context "when a word with arguments with a block that has no arguments" do
    let(:node) { ast("foo(a, b): a + b") }
    its(:name) { should == :foo }
    its(:arguments) { should == [ast("a"), ast("b")] }
    its(:receiver) { should be_nil }
    its(:proc_argument) { should be_nil }
    its(:block) { should == ast("{ a + b }") }
    its(:splat_argument) { should be_nil }
  end

  context "when a word followed by ! with arguments with a block that has no arguments" do
    let(:node) { ast("foo!(a, b): a + b") }
    its(:name) { should == :foo! }
    its(:arguments) { should == [ast("a"), ast("b")] }
    its(:receiver) { should be_nil }
    its(:proc_argument) { should be_nil }
    its(:block) { should == ast("{ a + b }") }
    its(:splat_argument) { should be_nil }
  end

  context "when a word followed by ? with arguments with a block that has no arguments" do
    let(:node) { ast("foo?(a, b): a + b") }
    its(:name) { should == :foo? }
    its(:arguments) { should == [ast("a"), ast("b")] }
    its(:receiver) { should be_nil }
    its(:proc_argument) { should be_nil }
    its(:block) { should == ast("{ a + b }") }
    its(:splat_argument) { should be_nil }
  end

  context "when a word with a block that has arguments" do
    let(:node) { ast("foo [a, b]: a + b") }
    its(:name) { should == :foo }
    its(:arguments) { should be_empty }
    its(:receiver) { should be_nil }
    its(:proc_argument) { should be_nil }
    its(:block) { should == ast("[a, b] { a + b }") }
    its(:splat_argument) { should be_nil }
  end

  context "when a word followed by ! with a block that has arguments" do
    let(:node) { ast("foo! [a, b]: a + b") }
    its(:name) { should == :foo! }
    its(:arguments) { should be_empty }
    its(:receiver) { should be_nil }
    its(:proc_argument) { should be_nil }
    its(:block) { should == ast("[a, b] { a + b }") }
    its(:splat_argument) { should be_nil }
  end

  context "when a word followed by ? with a block that has arguments" do
    let(:node) { ast("foo? [a, b]: a + b") }
    its(:name) { should == :foo? }
    its(:arguments) { should be_empty }
    its(:receiver) { should be_nil }
    its(:proc_argument) { should be_nil }
    its(:block) { should == ast("[a, b] { a + b }") }
    its(:splat_argument) { should be_nil }
  end

  context "when a word with arguments with a block that has arguments" do
    let(:node) { ast("foo(a, b) [a, b]: a + b") }
    its(:name) { should == :foo }
    its(:arguments) { should == [ast("a"), ast("b")] }
    its(:receiver) { should be_nil }
    its(:proc_argument) { should be_nil }
    its(:block) { should == ast("[a, b] { a + b }") }
    its(:splat_argument) { should be_nil }
  end

  context "when a word followed by ! with arguments with a block that has arguments" do
    let(:node) { ast("foo!(a, b) [a, b]: a + b") }
    its(:name) { should == :foo! }
    its(:arguments) { should == [ast("a"), ast("b")] }
    its(:receiver) { should be_nil }
    its(:proc_argument) { should be_nil }
    its(:block) { should == ast("[a, b] { a + b }") }
    its(:splat_argument) { should be_nil }
  end

  context "when a word followed by ? with arguments with a block that has arguments" do
    let(:node) { ast("foo?(a, b) [a, b]: a + b") }
    its(:name) { should == :foo? }
    its(:arguments) { should == [ast("a"), ast("b")] }
    its(:receiver) { should be_nil }
    its(:proc_argument) { should be_nil }
    its(:block) { should == ast("[a, b] { a + b }") }
    its(:splat_argument) { should be_nil }
  end

  context "when a node followed by a word" do
    let(:node) { ast("42 foo") }
    its(:name) { should == :foo }
    its(:arguments) { should be_empty }
    its(:receiver) { should == ast("42") }
    its(:proc_argument) { should be_nil }
    its(:block) { should be_nil }
    its(:splat_argument) { should be_nil }
  end

  context "when a node followed by a word followed by !" do
    let(:node) { ast("42 foo!") }
    its(:name) { should == :foo! }
    its(:arguments) { should be_empty }
    its(:receiver) { should == ast("42") }
    its(:proc_argument) { should be_nil }
    its(:block) { should be_nil }
    its(:splat_argument) { should be_nil }
  end

  context "when a node followed by a word followed by ?" do
    let(:node) { ast("42 foo?") }
    its(:name) { should == :foo? }
    its(:arguments) { should be_empty }
    its(:receiver) { should == ast("42") }
    its(:proc_argument) { should be_nil }
    its(:block) { should be_nil }
    its(:splat_argument) { should be_nil }
  end

  context "when a node followed by a word with arguments" do
    let(:node) { ast("42 foo(a, b)") }
    its(:name) { should == :foo }
    its(:arguments) { should == [ast("a"), ast("b")] }
    its(:receiver) { should == ast("42") }
    its(:proc_argument) { should be_nil }
    its(:block) { should be_nil }
    its(:splat_argument) { should be_nil }
  end

  context "when a node followed by a word followed by ! with arguments" do
    let(:node) { ast("42 foo!(a, b)") }
    its(:name) { should == :foo! }
    its(:arguments) { should == [ast("a"), ast("b")] }
    its(:receiver) { should == ast("42") }
    its(:proc_argument) { should be_nil }
    its(:block) { should be_nil }
    its(:splat_argument) { should be_nil }
  end

  context "when a node followed by a word followed by ? with arguments" do
    let(:node) { ast("42 foo?(a, b)") }
    its(:name) { should == :foo? }
    its(:arguments) { should == [ast("a"), ast("b")] }
    its(:receiver) { should == ast("42") }
    its(:proc_argument) { should be_nil }
    its(:block) { should be_nil }
    its(:splat_argument) { should be_nil }
  end

  context "when a node followed by a word with a proc argument" do
    let(:node) { ast("42 foo &blk") }
    its(:name) { should == :foo }
    its(:arguments) { should be_empty }
    its(:receiver) { should == ast("42") }
    its(:proc_argument) { should == ast("blk") }
    its(:block) { should be_nil }
    its(:splat_argument) { should be_nil }
  end

  context "when a node followed by a word followed by ! with a proc argument" do
    let(:node) { ast("42 foo! &blk") }
    its(:name) { should == :foo! }
    its(:arguments) { should be_empty }
    its(:receiver) { should == ast("42") }
    its(:proc_argument) { should == ast("blk") }
    its(:block) { should be_nil }
    its(:splat_argument) { should be_nil }
  end

  context "when a node followed by a word followed by ? with a proc argument" do
    let(:node) { ast("42 foo? &blk") }
    its(:name) { should == :foo? }
    its(:arguments) { should be_empty }
    its(:receiver) { should == ast("42") }
    its(:proc_argument) { should == ast("blk") }
    its(:block) { should be_nil }
    its(:splat_argument) { should be_nil }
  end

  context "when a node followed by a word with arguments with a proc argument" do
    let(:node) { ast("42 foo(a, b) &blk") }
    its(:name) { should == :foo }
    its(:arguments) { should == [ast("a"), ast("b")] }
    its(:receiver) { should == ast("42") }
    its(:proc_argument) { should == ast("blk") }
    its(:block) { should be_nil }
    its(:splat_argument) { should be_nil }
  end

  context "when a node followed by a word followed by ! with arguments with a proc argument" do
    let(:node) { ast("42 foo!(a, b) &blk") }
    its(:name) { should == :foo! }
    its(:arguments) { should == [ast("a"), ast("b")] }
    its(:receiver) { should == ast("42") }
    its(:proc_argument) { should == ast("blk") }
    its(:block) { should be_nil }
    its(:splat_argument) { should be_nil }
  end

  context "when a node followed by a word followed by ? with arguments with a proc argument" do
    let(:node) { ast("42 foo?(a, b) &blk") }
    its(:name) { should == :foo? }
    its(:arguments) { should == [ast("a"), ast("b")] }
    its(:receiver) { should == ast("42") }
    its(:proc_argument) { should == ast("blk") }
    its(:block) { should be_nil }
    its(:splat_argument) { should be_nil }
  end

  context "when a node followed by a word with a block that has no arguments" do
    let(:node) { ast("42 foo: a + b") }
    its(:name) { should == :foo }
    its(:arguments) { should be_empty }
    its(:receiver) { should == ast("42") }
    its(:proc_argument) { should be_nil }
    its(:block) { should == ast("{ a + b }") }
    its(:splat_argument) { should be_nil }
  end

  context "when a node followed by a word followed by ! with a block that has no arguments" do
    let(:node) { ast("42 foo!: a + b") }
    its(:name) { should == :foo! }
    its(:arguments) { should be_empty }
    its(:receiver) { should == ast("42") }
    its(:proc_argument) { should be_nil }
    its(:block) { should == ast("{ a + b }") }
    its(:splat_argument) { should be_nil }
  end

  context "when a node followed by a word followed by ? with a block that has no arguments" do
    let(:node) { ast("42 foo?: a + b") }
    its(:name) { should == :foo? }
    its(:arguments) { should be_empty }
    its(:receiver) { should == ast("42") }
    its(:proc_argument) { should be_nil }
    its(:block) { should == ast("{ a + b }") }
    its(:splat_argument) { should be_nil }
  end

  context "when a node followed by a word with arguments with a block that has no arguments" do
    let(:node) { ast("42 foo(a, b): a + b") }
    its(:name) { should == :foo }
    its(:arguments) { should == [ast("a"), ast("b")] }
    its(:receiver) { should == ast("42") }
    its(:proc_argument) { should be_nil }
    its(:block) { should == ast("{ a + b }") }
    its(:splat_argument) { should be_nil }
  end

  context "when a node followed by a word followed by ! with arguments with a block that has no arguments" do
    let(:node) { ast("42 foo!(a, b): a + b") }
    its(:name) { should == :foo! }
    its(:arguments) { should == [ast("a"), ast("b")] }
    its(:receiver) { should == ast("42") }
    its(:proc_argument) { should be_nil }
    its(:block) { should == ast("{ a + b }") }
    its(:splat_argument) { should be_nil }
  end

  context "when a node followed by a word followed by ? with arguments with a block that has no arguments" do
    let(:node) { ast("42 foo?(a, b): a + b") }
    its(:name) { should == :foo? }
    its(:arguments) { should == [ast("a"), ast("b")] }
    its(:receiver) { should == ast("42") }
    its(:proc_argument) { should be_nil }
    its(:block) { should == ast("{ a + b }") }
    its(:splat_argument) { should be_nil }
  end

  context "when a node followed by a word with a block that has arguments" do
    let(:node) { ast("42 foo [a, b]: a + b") }
    its(:name) { should == :foo }
    its(:arguments) { should be_empty }
    its(:receiver) { should == ast("42") }
    its(:proc_argument) { should be_nil }
    its(:block) { should == ast("[a, b] { a + b }") }
    its(:splat_argument) { should be_nil }
  end

  context "when a node followed by a word followed by ! with a block that has arguments" do
    let(:node) { ast("42 foo! [a, b]: a + b") }
    its(:name) { should == :foo! }
    its(:arguments) { should be_empty }
    its(:receiver) { should == ast("42") }
    its(:proc_argument) { should be_nil }
    its(:block) { should == ast("[a, b] { a + b }") }
    its(:splat_argument) { should be_nil }
  end

  context "when a node followed by a word followed by ? with a block that has arguments" do
    let(:node) { ast("42 foo? [a, b]: a + b") }
    its(:name) { should == :foo? }
    its(:arguments) { should be_empty }
    its(:receiver) { should == ast("42") }
    its(:proc_argument) { should be_nil }
    its(:block) { should == ast("[a, b] { a + b }") }
    its(:splat_argument) { should be_nil }
  end

  context "when a node followed by a word with arguments with a block that has arguments" do
    let(:node) { ast("42 foo(a, b) [a, b]: a + b") }
    its(:name) { should == :foo }
    its(:arguments) { should == [ast("a"), ast("b")] }
    its(:receiver) { should == ast("42") }
    its(:proc_argument) { should be_nil }
    its(:block) { should == ast("[a, b] { a + b }") }
    its(:splat_argument) { should be_nil }
  end

  context "when a node followed by a word followed by ! with arguments with a block that has arguments" do
    let(:node) { ast("42 foo!(a, b) [a, b]: a + b") }
    its(:name) { should == :foo! }
    its(:arguments) { should == [ast("a"), ast("b")] }
    its(:receiver) { should == ast("42") }
    its(:proc_argument) { should be_nil }
    its(:block) { should == ast("[a, b] { a + b }") }
    its(:splat_argument) { should be_nil }
  end

  context "when a node followed by a word followed by ? with arguments with a block that has arguments" do
    let(:node) { ast("42 foo?(a, b) [a, b]: a + b") }
    its(:name) { should == :foo? }
    its(:arguments) { should == [ast("a"), ast("b")] }
    its(:receiver) { should == ast("42") }
    its(:proc_argument) { should be_nil }
    its(:block) { should == ast("[a, b] { a + b }") }
    its(:splat_argument) { should be_nil }
  end

  context "when a node followed by a list" do
    let(:node) { ast("42 [a, b]") }
    its(:name) { should == :[] }
    its(:arguments) { should == [ast("a"), ast("b")] }
    its(:receiver) { should == ast("42") }
    its(:proc_argument) { should be_nil }
    its(:block) { should be_nil }
    its(:splat_argument) { should be_nil }
  end

  context "when an infix node" do
    let(:node) { ast("a + b") }
    its(:name) { should == :+ }
    its(:arguments) { should == [ast("b")] }
    its(:receiver) { should == ast("a") }
    its(:proc_argument) { should be_nil }
    its(:block) { should be_nil }
  end
end