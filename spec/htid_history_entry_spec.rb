# frozen_string_literal: true

RSpec.describe HathifileHistory::HTIDHistoryEntry do
  let(:entry) { described_class.new(htid: TEST_RECID, appeared_on: TEST_EARLIER_YYYYMM, last_seen_here: TEST_YYYYMM) }

  describe "#initialize" do
    it "is a HTIDHistoryEntry" do
      expect(entry).to be_a described_class
    end
  end

  describe "#existed_here_on" do
    context "with an earler date" do
      it "returns false" do
        expect(entry.existed_here_on(TEST_LATER_YYYYMM)).to eq false
      end
    end

    context "with a later date" do
      it "returns true" do
        expect(entry.existed_here_on(TEST_YYYYMM)).to eq true
      end
    end
  end

  describe "#to_json" do
    it "produces a JSON string" do
      json = entry.to_json
      expect(json).to be_a String
      expect(json).to match(/json_class/)
    end
  end

  describe ".json_create" do
    it "produces an identical copy" do
      old_entry = entry
      json = old_entry.to_json
      new_entry = JSON.parse(json, create_additions: true)
      expect(new_entry).to be_a described_class
      expect(new_entry.appeared_on).to eq old_entry.appeared_on
      expect(new_entry.last_seen_here).to eq old_entry.last_seen_here
    end
  end
end
