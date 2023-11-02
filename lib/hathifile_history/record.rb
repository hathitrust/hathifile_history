# frozen_string_literal: true

require_relative "htid_history_entry"

require "json"

module HathifileHistory
  class Record
    attr_accessor :recid, :entries, :most_recently_seen, :current_entries, :current_htids

    def initialize(recid)
      @recid = recid
      @entries = {}
      @most_recently_seen = 0
      @current_entries = Set.new
      @current_htids = Set.new

      @json_create_id = JSON.create_id.freeze
      @classname = self.class.name.freeze
    end

    def seen_on_or_after?(yyyymm)
      @most_recently_seen >= yyyymm
    end

    def see(htid, yyyymm)
      @most_recently_seen = yyyymm if yyyymm > @most_recently_seen
      if entries[htid]
        entries[htid].last_seen_here = yyyymm
      else
        entries[htid] = HTIDHistoryEntry.new(htid: htid, appeared_on: yyyymm, last_seen_here: yyyymm)
      end
    end

    def compute_current!(yyyymm)
      @current_entries = Set.new
      @current_htids = Set.new

      # Nothing is "current" if the record doesn't even exist anymore
      return unless most_recently_seen == yyyymm

      entries.each_pair do |htid, hist|
        if hist.existed_here_on(yyyymm)
          current_entries << hist
          current_htids << htid
        end
      end
    end

    def remove(htid)
      entries.delete(htid)
    end

    # @param [Hash] current_records The hash of htid-to-record created by calls
    # to Records#add or Records#add_record
    def remove_dead_htids!(current_records)
      entries.each_pair do |htid, hist|
        remove(htid) unless current_records[htid]
      end
    end

    def to_json(*)
      {
        :recid => @recid,
        :mrs => @most_recently_seen,
        :entries => entries,
        @json_create_id => @classname
      }.to_json(*)
    end

    # @param [Hash] Result of json-parsing data from the ndj
    def self.json_create(rec)
      r = new(rec["recid"])
      r.most_recently_seen = rec["mrs"]
      r.entries = rec["entries"]
      r
    end
  end
end
