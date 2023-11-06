# frozen_string_literal: true

require "json"
require "milemarker"
require "logger"
require "zinzout"

require_relative "htid_history_entry"
require_relative "record"

module HathifileHistory
  # Records is the umbrella object -- essentially a big list of records with data about
  # which HT items have been on it, when they appeared, and when they last showed up in
  # a Hathifile
  class Records
    LEADING_ZEROS = /\A0+/
    EMPTY = ""

    attr_accessor :logger, :newest_load
    attr_reader :records

    def initialize
      @current_record_for = {}
      @records = {}
      @newest_load = 0
      @logger = Logger.new($stdout)
    end

    # @pararm [Integer] recid The record id as an integer
    # @return [Record] the Record with that id
    def [](recid)
      @records[recid]
    end

    # Optionally (but usually) derive the YYYYMM from the given hathifile
    # and add all the hathifile lines
    # @param [String] hathifile The name of the hathifile to load
    # @param [Integer] yyyymm The Year/Month as a six-digit integer (like 202111)
    # @return [Records] self
    def add_monthly(hathifile, yyyymm: nil)
      yyyymm ||= yyyymm_from_filename(hathifile)
      basename = Pathname.new(hathifile).basename.to_s
      process_name = "add from #{basename}"
      logger.info process_name
      mm = Milemarker.new(batch_size: 2_000_000, name: process_name, logger: logger)
      Zinzout.zin(hathifile).each do |line|
        add_hathifile_line_by_date(line, yyyymm)
        mm.increment_and_log_batch_line
      end
      mm.log_final_line
      self
    end

    # Add the given hathifile_line as read on the given yyyymm
    # Some hathifiles have errors (ususally unicode problems),
    # in which case we cast the hathifile_line to act as a binary string
    # and try to parse out the columns we need again.
    # @param [String] hathifile_line A line from a hathifile
    # @param [Integer] yyyymm The Year/Month of that hathifile as a six-digit integer (like 202111)
    # @return [Records] self
    def add_hathifile_line_by_date(hathifile_line, yyyymm)
      errored = false
      begin
        htid, recid = ids_from_line(hathifile_line)
        add(htid: htid, recid: recid, yyyymm: yyyymm)
      rescue => e
        if !errored
          errored = true
          hathifile_line = hathifile_line.b # probably bad unicode, so just treat it as binary
          retry
        else
          logger.warn "(#{e}) -- #{hathifile_line}"
        end
      end
      self
    end

    # Tell the record identified by recid to "see" the given htid.
    # Creates a new Record if need be.
    # @param [String] htid The htid seen in the hathfile
    # @param [Integer] recid The record on which it was seen
    # @param [Integer] yyyymm The year/month on which it was seen
    # @return [Records] self
    def add(htid:, recid:, yyyymm:)
      @newest_load = yyyymm if yyyymm > @newest_load
      @records[recid] ||= Record.new(recid)
      @records[recid].see(htid, yyyymm)
      self
    end

    # @param [Record] rec A fully-hydrated record, probably loaded from a save file
    # @return [Records] self
    def add_record(rec)
      @newest_load = rec.most_recently_seen if @newest_load < rec.most_recently_seen
      @records[rec.recid] = rec
      self
    end

    # @param [String] line A hathifile_line from a hathifile
    # @return [Array<String, Integer>] The htid and recid in this hathifile_line
    def ids_from_line(line)
      htid, recid_str = line.chomp.split("\t", 5).values_at(0, 3)
      htid.freeze
      recid = intify_record_id(recid_str)
      [htid, recid]
    end

    # Given an ndj file produced by #dump_to_ndj, read it back in to a new Records object
    # @param [String] filename from a previous call to #dump_to_ndj
    # @param [#info] logger A logger
    # @return [Records] a full Records object with all that data
    def self.load_from_ndj(file_from_dump_to_ndj, logger: Logger.new($stdout))
      recs = new
      basename = Pathname.new(file_from_dump_to_ndj).basename
      mm = Milemarker.new(batch_size: 500_000, name: "load #{basename}", logger: logger)
      logger.info "Loading #{file_from_dump_to_ndj}"

      Zinzout.zin(file_from_dump_to_ndj).each do |line|
        record = JSON.parse(line, create_additions: true)
        recs.add_record(record)
        mm.increment_and_log_batch_line
      end
      mm.log_final_line
      recs
    end

    # Dump the entire Records object to newline-delimited json for safe keeping
    # @param [String] outfile
    def dump_to_ndj(outfile)
      basename = Pathname.new(outfile).basename.to_s
      process = "dump to #{basename}"
      logger.info process
      mm = Milemarker.new(batch_size: 2_000_000, name: process, logger: logger)
      Zinzout.zout(outfile) do |out|
        @records.each_pair do |_recid, rec|
          out.puts rec.to_json
          mm.increment_and_log_batch_line
        end
      end
      mm.log_final_line
    end

    # Any "current" (seen this load) htid will be added to its record's
    # current_* sets and added to the current_record_of[htid] = rec hash
    def compute_current_sets!(yyyymm = newest_load)
      mm = Milemarker.new(batch_size: 500_000, name: "compute_current_sets", logger: logger)
      @records.each_pair do |recid, rec|
        next unless rec.seen_on_or_after?(yyyymm)
        rec.compute_current!(yyyymm)
        rec.current_entries.each { |hist| @current_record_for[hist.htid] = rec }
        mm.increment_and_log_batch_line
      end
      mm.log_final_line
    end

    def current_record_for(htid)
      @current_record_for[htid]
    end

    # @return [Hash] Valid redirect pairs of the form old_dead_record -> current_record
    def redirects
      redirs = {}
      each_deleted_record do |rec|
        new_recids = rec.entries.keys.map { |htid| current_record_for(htid).recid }.uniq
        if new_recids.size == 1
          redirs[rec.recid] = new_recids.first
        end
      end
      redirs
    end

    # A "dead" htid is one that doesn't appear in the current load, and hence was never
    # added to @current_record_for
    def remove_dead_htids!
      raise "Can't call #remove_dead_htids! before calling #compute_current_sets!" if @current_record_for.size == 0
      @records.each_pair do |recid, rec|
        rec.remove_dead_htids!(@current_record_for)
      end
    end

    # Needed because we get record ids with leading zeros, which ruby
    # really wants to interpret as oct
    # @param [String] str a string of digits
    # @return [Integer] The integer equivalent.
    def intify_record_id(str)
      str.gsub(LEADING_ZEROS, EMPTY).to_i
    end

    # @param [String] Filename of the form hathi_*_20111101*
    # @return [Integer] A six digit string of the form YYYYMM representing the year/month
    def self.yyyymm_from_filename(filename, logger: Logger.new($stdout))
      fulldate = filename.gsub(/\D/, "")
      yyyymm = Integer(fulldate[0..-3], exception: false)
      if yyyymm.nil?
        logger.error "Can't get yyyymm from filename '#{filename}'. Aborting"
        exit 1
      end
      yyyymm
    end

    def yyyymm_from_filename(*args)
      self.class.yyyymm_from_filename(*args)
    end

    # A convenience method to get an iterator for only deleted records
    # (i.e., those that haven't been seen in the newest load)
    # Do this instead of records.values.each ... to avoid creating
    # the giant intermediate array. Could just use #lazy, maybe?
    def each_deleted_record
      return enum_for(:each_deleted_record) unless block_given?
      records.each_pair do |recid, rec|
        if rec.most_recently_seen < newest_load
          yield rec
        end
      end
    end
  end
end
