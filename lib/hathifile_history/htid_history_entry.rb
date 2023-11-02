# frozen_string_literal: true

require "json"

module HathifileHistory
  class HTIDHistoryEntry
    attr_accessor :htid, :appeared_on, :last_seen_here

    def initialize(htid:, appeared_on:, last_seen_here:)
      @htid = htid
      @appeared_on = appeared_on
      @last_seen_here = last_seen_here

      @json_create_id = JSON.create_id.freeze
      @classname = self.class.name.freeze
    end

    def existed_here_on(yyyymm)
      @last_seen_here >= yyyymm
    end

    def to_json(*)
      {:htid => @htid, :app => @appeared_on, :lsh => @last_seen_here, @json_create_id => @classname}.to_json(*)
    end

    # @param [Hash] hist result of json-parsing the ndj hathifile_line
    def self.json_create(hist)
      new(htid: hist["htid"], appeared_on: hist["app"], last_seen_here: hist["lsh"])
    end
  end
end
