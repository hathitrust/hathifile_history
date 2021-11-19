# frozen_string_literal: true

require 'logger'
require 'zinzout'
require 'set'
require 'waypoint'
require 'json'

class HistoryEntry
  attr_accessor :htid, :appeared_on, :last_seen_here

  def initialize(htid:, appeared_on:, last_seen_here:)
    @htid           = htid
    @appeared_on    = appeared_on
    @last_seen_here = last_seen_here

    @json_create_id = JSON.create_id.freeze
    @classname      = self.class.name.freeze
  end

  def existed_here_on(yyyymm)
    @last_seen_here >= yyyymm
  end

  def to_json(*args)
    { htid: @htid, app: @appeared_on, lsh: @last_seen_here, @json_create_id => @classname }.to_json(*args)
  end

  #@param [Hash] hist result of json-parsing the ndj hathifile_line
  def self.json_create(hist)
    self.new(htid: hist['htid'], appeared_on: hist['app'], last_seen_here: hist['lsh'])
  end
end

class Record
  attr_accessor :recid, :entries, :most_recently_seen, :current_entries, :current_htids

  def initialize(recid)
    @recid              = recid
    @entries            = {}
    @most_recently_seen = 0
    @current_entries    = Set.new
    @current_htids      = Set.new

    @json_create_id = JSON.create_id.freeze
    @classname      = self.class.name.freeze
  end

  def seen_on_or_after?(yyyymm)
    @most_recently_seen >= yyyymm
  end

  def see(htid, yyyymm)
    @most_recently_seen = yyyymm if yyyymm > @most_recently_seen
    if entries[htid]
      entries[htid].last_seen_here = yyyymm
    else
      entries[htid] = HistoryEntry.new(htid: htid, appeared_on: yyyymm, last_seen_here: yyyymm)
    end
  end

  def compute_current!(yyyymm)
    @current_entries = Set.new
    @current_htids   = Set.new

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

  #@param [Hash] current_records The hash of htid-to-record created by calls
  # to Records#add or Records#add_record
  def remove_dead_htids!(current_records)
    entries.each_pair do |htid, hist|
      remove(htid) unless current_records[htid]
    end
  end

  def to_json(*args)
    {
      recid:          @recid,
      mrs:            @most_recently_seen,
      entries:        entries,
      @json_create_id => @classname
    }.to_json(*args)
  end

  #@param [Hash] Result of json-parsing data from the ndj
  def self.json_create(rec)
    r                    = self.new(rec['recid'])
    r.most_recently_seen = rec['mrs']
    r.entries            = rec['entries']
    r
  end
end

class Records

  LEADING_ZEROS = /\A0+/.freeze
  EMPTY         = ''.freeze

  attr_accessor :logger, :newest_load
  attr_reader :records

  def initialize
    @current_record_for = {}
    @records            = {}
    @newest_load        = 0
    @logger             = Logger.new(STDOUT)
  end

  def [](recid)
    @records[recid]
  end

  # Optionally (but usually) derive the YYYYMM from the given hathifile
  # and add all the hathifile lines
  # @param [String] hathifile The name of the hathifile to load
  def add_monthly(hathifile, yyyymm: nil)
    yyyymm ||= yyyymm_from_filename(hathifile)

    process_name = "add from #{hathifile}"
    logger.info process_name
    waypoint = Waypoint.new(batch_size: 2_000_000, file_or_process: process_name)
    Zinzout.zin(hathifile).each do |line|
      add_hathifile_line_by_date(line, yyyymm)
      waypoint.incr
      waypoint.on_batch { |wp| logger.info waypoint.batch_line }
    end
    logger.info waypoint.final_line
    self
  end

  # Add the given hathifile_line as read on the given yyyymm
  # Some hathifiles have errors (ususally unicode problems),
  # in which case we cast the hathifile_line to act as a binary string
  # and try to parse out the columns we need again.
  def add_hathifile_line_by_date(hathifile_line, yyyymm)
    errored = false
    begin
      htid, recid = ids_from_line(hathifile_line)
      add(htid: htid, recid: recid, yyyymm: yyyymm)
    rescue => e
      if !errored
        errored = true
        hathifile_line    = hathifile_line.b # probably bad unicode, so just treat it as binary
        retry
      else
        logger.warn "(#{e}) -- #{hathifile_line}"
      end
    end
  end

  # Tell the record identified by recid to "see" the given htid.
  # Creates a new Record if need be.
  def add(htid:, recid:, yyyymm:)
    @newest_load    = yyyymm if yyyymm > @newest_load
    @records[recid] ||= Record.new(recid)
    @records[recid].see(htid, yyyymm)
    self
  end

  #@param [Record] rec A fully-hydrated record
  def add_record(rec)
    @newest_load        = rec.most_recently_seen if @newest_load < rec.most_recently_seen
    @records[rec.recid] = rec
    self
  end

  #@param [String] line A hathifile_line from a hathifile
  #@return [Array<String, Integer>] The htid and recid in this hathifile_line
  def ids_from_line(line)
    htid, recid_str = line.chomp.split(/\t/, 4).values_at(0, 3)
    htid.freeze
    recid = intify(recid_str)
    [htid, recid]
  end

  # Given an ndj file produced by #dump_to_ndj, read it back in to a new Records object
  def self.load_from_ndj(file_from_dump_to_ndj, logger: Logger.new(STDOUT))
    recs = self.new
    wp = Waypoint.new(batch_size: 500_000, file_or_process: "load #{file_from_dump_to_ndj}")
    Zinzout.zin(file_from_dump_to_ndj).each do |line|
      record = JSON.parse(line, create_additions: true)
      recs.add_record(record)
      wp.incr
      wp.on_batch { logger.info wp.batch_line }
    end
    recs
  end

  def dump_to_ndj(outfile)
    process = "dump to #{outfile}"
    logger.info process
    wp = Waypoint.new(batch_size: 2_000_000, file_or_process: process)
    Zinzout.zout(outfile) do |out|
      @records.each_pair do |recid, rec|
        out.puts rec.to_json
        wp.incr
        wp.on_batch { logger.info wp.batch_line }
      end
    end
    logger.info wp.final_line
  end

  # Any "current" (seen this load) htid will be added to its record's
  # current_* sets and added to the current_record_of[htid] = rec hash
  def compute_current_sets!(yyyymm = newest_load)
    wp = Waypoint.new(batch_size: 500_000, file_or_process: "compute_current_sets")
    @records.each_pair do |recid, rec|
      next unless rec.seen_on_or_after?(yyyymm)

      rec.compute_current!(yyyymm)
      rec.current_entries.each { |hist| @current_record_for[hist.htid] = rec }
      wp.incr
      wp.on_batch { logger.info wp.batch_line }
    end
    logger.info wp.final_line
  end

  def current_record_for(htid)
    @current_record_for[htid]
  end

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

  def self.yyyymm_from_filename(filename)
    fulldate = filename.gsub(/\D/, '')
    yyyymm   = Integer(fulldate[0..-3])
  end

  # Needed because we get numbers with leading zeros, which ruby
  # really wants to interpret as oct
  #@param [String] str a string of digits
  #@return [Integer] The integer equivalent.
  def intify(str)
    str.gsub!(LEADING_ZEROS, EMPTY)
    str.to_i
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

__END__

recs = Records.new

recs.add_monthly('hathi_full_20121001.txt.gz')
recs.add_monthly('hathi_full_20211101.txt.gz')

recs.dump_to_ndj('202111.ndj.gz')

recs.compute_current_sets!(recs.newest_load)
recs.remove_dead_htids!

Zinzout.zout('202111_redirects.txt') do |out|
  recs.redirects.each_pair do |source, sink|
    out.puts "%09d\t%09d" % [source, sink]
  end
end
