# frozen_string_literal: true

# NOTE: 000004165 is a redirect

VALID_LINE = "#{TEST_HTID}\tdeny\tic\t#{TEST_RECID}\tother fields..."
INVALID_BYTE_SEQUENCE_LINE = VALID_LINE + "\xFFFF"
UNPARSEABLE_LINE = ""

RSpec.describe HathifileHistory::Records do
  let(:records) do
    described_class.new(logger: NullLogger.new($stdout))
  end

  describe "#initialize" do
    it "is a HathifileHistory::Records" do
      expect(records).to be_a described_class
    end

    it "has records hash" do
      expect(records.records).to be_a Hash
    end
  end

  describe "#[]" do
    context "with a valid record id" do
      it "gets a record" do
        new_rec = HathifileHistory::Record.new TEST_RECID
        recs = records.add_record(new_rec)
        expect(recs[TEST_RECID]).to be_a HathifileHistory::Record
      end
    end

    context "with a bogus record id" do
      it "gets a record" do
        new_rec = HathifileHistory::Record.new TEST_RECID
        recs = records.add_record(new_rec)
        expect(recs[TEST_BOGUS_RECID]).to be_nil
      end
    end
  end

  describe "#add_monthly" do
    it "does not raise error" do
      fixture = File.join(FIXTURES_DIR, TEST_SAMPLE_HATHIFILE_NAME)
      expect { records.add_monthly(fixture) }.not_to raise_error
    end
  end

  describe "#add_hathifile_line_by_date" do
    context "with a well-formed line" do
      it "parses recid and htid" do
        rec = records.add_hathifile_line_by_date(VALID_LINE, TEST_YYYYMM)
        expect(rec.records.count).to eq 1
      end
    end

    context "with a line having Unicode issues" do
      it "parses recid and htid" do
        rec = records.add_hathifile_line_by_date(INVALID_BYTE_SEQUENCE_LINE, TEST_YYYYMM)
        expect(rec.records.count).to eq 1
      end
    end

    context "with a bogus line" do
      it "parses recid and htid" do
        rec = records.add_hathifile_line_by_date(UNPARSEABLE_LINE, TEST_YYYYMM)
        expect(rec.records.count).to eq 0
      end
    end
  end

  describe "#add" do
    it "adds a record" do
      recs = records.add(htid: TEST_HTID, recid: TEST_RECID, yyyymm: TEST_YYYYMM)
      expect(recs.records).not_to be_empty
    end

    it "bumps newest_load" do
      recs = records.add(htid: TEST_HTID, recid: TEST_RECID, yyyymm: TEST_YYYYMM)
      expect(recs.newest_load).to eq TEST_YYYYMM
    end

    it "maintains newest_load if newer" do
      recs = records.add(htid: TEST_HTID, recid: TEST_RECID, yyyymm: TEST_YYYYMM)
      recs.add(htid: TEST_HTID_1, recid: TEST_RECID_1, yyyymm: TEST_EARLIER_YYYYMM)
      expect(recs.newest_load).to eq TEST_YYYYMM
    end
  end

  describe "#add_record" do
    it "adds a record" do
      new_rec = HathifileHistory::Record.new TEST_RECID
      recs = records.add_record(new_rec)
      expect(recs.records).not_to be_empty
    end

    it "bumps newest_load" do
      rec = HathifileHistory::Record.new TEST_RECID
      rec.see TEST_HTID, TEST_YYYYMM
      recs = records.add_record(rec)
      expect(recs.newest_load).to eq TEST_YYYYMM
    end

    it "maintains newest_load if newer" do
      rec = HathifileHistory::Record.new TEST_RECID
      rec.see TEST_HTID, TEST_YYYYMM
      recs = records.add_record(rec)
      rec = HathifileHistory::Record.new TEST_RECID_1
      rec.see TEST_HTID_1, TEST_EARLIER_YYYYMM
      recs.add_record(rec)
      expect(recs.newest_load).to eq TEST_YYYYMM
    end
  end

  describe "#ids_from_line" do
    context "with a well-formed line" do
      it "parses recid and htid" do
        htid, cid = records.ids_from_line VALID_LINE
        expect([htid, cid]).to eq [TEST_HTID, 0]
      end
    end

    context "with a line having Unicode issues" do
      it "parses recid and htid" do
        expect { records.ids_from_line INVALID_BYTE_SEQUENCE_LINE }.to raise_error ArgumentError
      end
    end

    context "with a bogus line" do
      it "raises" do
        expect { records.ids_from_line UNPARSEABLE_LINE }.to raise_error NoMethodError
      end
    end
  end

  describe ".load_from_ndj" do
    it "does not raise" do
      fixture = File.join(FIXTURES_DIR, TEST_NDJ_FILE)
      logger = NullLogger.new($stdout)
      expect { described_class.load_from_ndj(fixture, logger: logger) }.not_to raise_error
    end
  end

  describe "#dump_to_ndj" do
    it "creates readable dump file" do
      recs = records.add(htid: TEST_HTID, recid: TEST_RECID, yyyymm: TEST_YYYYMM)
      recs.dump_to_ndj TEST_NDJ_FILE
      expect(File.readable?(TEST_NDJ_FILE)).to eq true
    end
  end

  describe "#current_record_for" do
    it "is initially empty" do
      recs = records.add(htid: TEST_HTID, recid: TEST_RECID, yyyymm: TEST_YYYYMM)
      expect(recs.current_record_for(TEST_HTID)).to be_nil
    end

    it "is is populated by #compute_current_sets!" do
      recs = records.add(htid: TEST_HTID, recid: TEST_RECID, yyyymm: TEST_YYYYMM)
      recs.logger = nil
      recs.compute_current_sets! TEST_YYYYMM
      expect(recs.current_record_for(TEST_HTID)).not_to be_nil
    end
  end

  describe "#redirects" do
    it "returns non-empty Hash of redirects" do
      recs = records
      recs.add_monthly File.join(FIXTURES_DIR, TEST_OLDER_SAMPLE_HATHIFILE_NAME)
      recs.add_monthly File.join(FIXTURES_DIR, TEST_SAMPLE_HATHIFILE_NAME)
      recs.compute_current_sets!(recs.newest_load)
      recs.remove_dead_htids!
      redirects = recs.redirects
      expect(redirects).not_to be_empty
      expect(redirects.keys.all? { |x| x.instance_of?(Integer) }).to eq true
      expect(redirects.values.all? { |x| x.instance_of?(Integer) }).to eq true
    end
  end

  describe "#remove_dead_htids!" do
    context "with previous call to #compute_current_sets!" do
      it "populates current_record_for" do
        recs = records.add(htid: TEST_HTID, recid: TEST_RECID, yyyymm: TEST_YYYYMM)
        recs.remove_dead_htids!
        expect(recs.current_record_for(TEST_HTID)).not_to be_nil
      end
    end
  end

  describe "#intify_record_id" do
    it "removes leading zeroes and returns Integer" do
      cases = {"0000001" => 1, "1" => 1, "1000000" => 1000000, "nonsense" => 0}
      cases.each_pair do |record_id, int|
        expect(records.intify_record_id(record_id)).to eq int
      end
    end
  end

  describe ".yyyymm_from_filename" do
    context "with a valid filename" do
      it "returns YYYYMM" do
        expect(described_class.yyyymm_from_filename(TEST_VALID_HATHIFILE_NAME)).to eq TEST_YYYYMM.to_i
      end
    end

    context "with an invalid filename" do
      it "raises" do
        expect { described_class.yyyymm_from_filename "blah" }.to raise_error(SystemExit)
      end
    end
  end

  describe "#yyyymm_from_filename" do
    context "with a valid filename" do
      it "returns YYYYMM" do
        expect(records.yyyymm_from_filename(TEST_VALID_HATHIFILE_NAME)).to eq TEST_YYYYMM.to_i
      end
    end

    context "with an invalid filename" do
      it "raises" do
        expect { records.yyyymm_from_filename "blah" }.to raise_error(SystemExit)
      end
    end
  end

  describe "#each_deleted_record" do
    context "with no block" do
      it "returns enumerator" do
        recs = records
        recs.add_monthly File.join(FIXTURES_DIR, TEST_OLDER_SAMPLE_HATHIFILE_NAME)
        recs.add_monthly File.join(FIXTURES_DIR, TEST_SAMPLE_HATHIFILE_NAME)
        expect(recs.each_deleted_record).to be_a Enumerator
      end
    end

    context "with a block" do
      it "yields one or more Record instances" do
        recs = records
        recs.add_monthly File.join(FIXTURES_DIR, TEST_OLDER_SAMPLE_HATHIFILE_NAME)
        recs.add_monthly File.join(FIXTURES_DIR, TEST_SAMPLE_HATHIFILE_NAME)
        yielded_records = []
        recs.each_deleted_record do |rec|
          yielded_records << rec
        end
        expect(yielded_records.count).to be > 0
      end
    end
  end
end
