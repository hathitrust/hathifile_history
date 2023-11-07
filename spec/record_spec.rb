# frozen_string_literal: true

RSpec.describe HathifileHistory::Record do
  let(:record) { described_class.new(TEST_RECID) }

  describe "#initialize" do
    it "is a HathifileHistory::Record" do
      expect(record).to be_a described_class
    end

    it "has same recid as it was created with" do
      expect(record.recid).to eq TEST_RECID
    end

    it "has entries hash" do
      expect(record.entries).to be_a Hash
    end
  end

  describe "#seen_on_or_after?" do
    context "with earlier date" do
      it "returns true" do
        rec = record
        rec.see(TEST_HTID, TEST_YYYYMM)
        expect(rec.seen_on_or_after?(TEST_EARLIER_YYYYMM)).to eq true
      end
    end

    context "with later date" do
      it "returns false" do
        rec = record
        rec.see(TEST_HTID, TEST_YYYYMM)
        expect(rec.seen_on_or_after?(TEST_LATER_YYYYMM)).to eq false
      end
    end
  end

  describe "#see" do
    it "updates #most_recently_seen" do
      rec = record
      rec.see(TEST_HTID, TEST_YYYYMM)
      expect(rec.most_recently_seen).to eq TEST_YYYYMM
    end

    it "keeps later #most_recently_seen" do
      rec = record
      rec.see(TEST_HTID, TEST_YYYYMM)
      rec.see(TEST_HTID, TEST_EARLIER_YYYYMM)
      expect(rec.most_recently_seen).to eq TEST_YYYYMM
    end
  end

  describe "#compute_current!" do
    context "with a current record" do
      it "populates current_entries and current_htids" do
        rec = record
        rec.see(TEST_HTID, TEST_EARLIER_YYYYMM)
        rec.see(TEST_HTID, TEST_YYYYMM)
        rec.compute_current! TEST_YYYYMM
        expect(rec.current_entries).not_to be_empty
        expect(rec.current_htids).not_to be_empty
      end
    end

    context "with an old record" do
      it "does not populate current_entries or current_htids" do
        rec = record
        rec.see(TEST_HTID, TEST_EARLIER_YYYYMM)
        rec.compute_current! TEST_YYYYMM
        expect(rec.current_entries).to be_empty
        expect(rec.current_htids).to be_empty
      end
    end
  end

  describe "#remove" do
    it "removes htid from entries hash" do
      rec = record
      rec.see(TEST_HTID, TEST_YYYYMM)
      rec.remove TEST_HTID
      expect(rec.entries[TEST_HTID]).to be_nil
    end
  end

  describe "#remove_dead_htids!" do
    context "with current_records not including this one" do
      it "removes htid" do
        rec = record
        rec.see(TEST_HTID, TEST_YYYYMM)
        rec.remove_dead_htids!(**{"test.SOME_OTHER_HTID" => {}})
        expect(rec.entries).to be_empty
      end
    end

    context "with current_records including this one" do
      it "does not remove htid" do
        rec = record
        rec.see(TEST_HTID, TEST_YYYYMM)
        rec.remove_dead_htids!(**{TEST_HTID => {}})
        expect(rec.entries).not_to be_empty
      end
    end
  end

  describe "#to_json" do
    it "produces a JSON string" do
      json = record.to_json
      expect(json).to be_a String
      expect(json).to match(/json_class/)
    end
  end

  describe ".json_create" do
    it "produces an identical copy" do
      rec = record
      json = rec.to_json
      new_rec = JSON.parse(json, create_additions: true)
      expect(new_rec).to be_a described_class
      # expect(json).to be_a String
      expect(new_rec.entries).to eq rec.entries
    end
  end
end
