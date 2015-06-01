require "spec_helper"

require "atomy/module"
require "atomy/pattern/wildcard"

describe Atomy::Pattern::Wildcard do
  describe "#name" do
    context "when no name is given" do
      subject { described_class.new }

      it "returns nil" do
        expect(subject.name).to be_nil
      end
    end

    context "when a name is given" do
      subject { described_class.new(:abc) }

      it "returns the name" do
        expect(subject.name).to eq(:abc)
      end
    end
  end

  describe "#matches?" do
    it { should === nil }
    it { should === Object.new }
  end

  describe "#locals" do
    context "when no name is given" do
      it "returns an empty array" do
        expect(subject.locals).to be_empty
      end
    end

    context "when a name is given" do
      subject { described_class.new(:abc) }

      it "returns a list containing the name" do
        expect(subject.locals).to eq([:abc])
      end
    end
  end

  describe "#assign" do
    context "when no name is given" do
      subject { described_class.new }

      it "does nothing" do
        subject.assign(Rubinius::VariableScope.current, nil)
      end
    end

    context "when a name is given" do
      subject { described_class.new(:abc) }

      it "assigns the name in the given scope" do
        abc = nil
        subject.assign(Rubinius::VariableScope.current, 42)
        expect(abc).to eq(42)
      end
    end
  end

  describe "#precludes?" do
    it "returns true" do
      expect(subject.precludes?(double)).to eq(true)
    end
  end
end
