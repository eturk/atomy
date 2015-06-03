require "spec_helper"

require "atomy/module"
require "atomy/node/equality"
require "atomy/pattern/equality"
require "atomy/pattern/splat"
require "atomy/pattern/wildcard"

describe Atomy::Pattern::Splat do
  subject { described_class.new(Atomy::Pattern.new) }

  describe "#pattern" do
    let(:pattern) { Atomy::Pattern.new }

    subject { described_class.new(pattern) }

    it "returns the pattern" do
      expect(subject.pattern).to eq(pattern)
    end
  end

  describe "#matches?" do
    class SomePattern
      def matches?(gen)
        gen.push_literal(:some_pattern)
        gen.send(:==, 1)
      end
    end

    subject { described_class.new(SomePattern.new) }

    it_compiles_as(:matches?) do |gen|
      gen.push_literal(:some_pattern)
      gen.send(:==, 1)
    end
  end

  describe "#bindings" do
    context "when its pattern binds" do
      subject { described_class.new(Atomy::Pattern::Wildcard.new(:abc)) }

      it "returns the bound values" do
        expect(subject.bindings([ast("foo"), ast("bar")])).to eq([[ast("foo"), ast("bar")]])
      end
    end

    context "when its pattern does NOT bind" do
      subject { described_class.new(Atomy::Pattern::Wildcard.new) }

      it "returns no bindings" do
        expect(subject.bindings([ast("foo"), ast("bar")])).to be_empty
      end
    end
  end
end

