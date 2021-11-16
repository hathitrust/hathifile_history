# frozen_string_literal: true

require 'zinzout'
require 'json'

require_relative 'generic_history'
require_relative 'htid_history'
require_relative 'recid_history'
require_relative 'id_date'
require 'logger'

require 'waypoint'

class HathifileHistory

  LEADING_ZEROS = /\A0+/.freeze
  EMPTY         = ''.freeze

  attr_accessor :logger

  def initialize
    @htid_history  = {}
    @recid_history = {}
    @logger        = Logger.new(STDOUT)
  end

  def htid_history_hash
    @htid_history
  end

  alias_method :htids, :htid_history_hash

  def recid_history_hash
    @recid_history
  end

  alias_method :recids, :recid_history_hash

  # @return [HTIDHistory]
  def htid_history(htid)
    @htid_history[htid] ||= HTIDHistory.new(htid)
  end

  def recid_history(recid)
    @recid_history[recid] ||= RecIDHistory.new(recid)
  end

  def has_htid(htid)
    htid_history_hash.has_key?(htid)
  end

  def has_recid(recid)
    recid_history_hash.has_key?(recid)
  end

  def current_record(htid)
    return nil unless has_htid(htid)
    apps = htid_history(htid).appearances.sort { |a, b| a.dt <=> b.dt }
    recid_history(apps.last.id)
  end

  def add_hathifile_line_by_date(line, dt)
    errored = false
    begin
      htid, recid_str = line.chomp.split(/\t/, 4).values_at(0, 3)
      htid.freeze
      recid = intify(recid_str)

      htid_history(htid).add(IDDate.new(recid, dt))
      recid_history(recid).add(IDDate.new(htid, dt))
    rescue => e
      if !errored
        errored = true
        line    = line.b
        retry
      else
        logger.warn "(#{e}) -- #{line}"
      end
    end
  end

  def self.yyyymm_from_filename(filename)
    fulldate = filename.gsub(/\D/, '')
    yyyymm   = Integer(fulldate[0..-3])
  end

  def yyyymm_from_filename(*args)
    self.class.yyyymm_from_filename(*args)
  end

  def add_monthly(filename, yearmonth: nil)
    yearmonth ||= yyyymm_from_filename(filename)

    process_name = "add from #{filename}"
    logger.info process_name
    waypoint = Waypoint.new(batch_size: 2_000_000, file_or_process: process_name)
    Zinzout.zin(filename).each do |line|
      self.add_hathifile_line_by_date(line, yearmonth)
      waypoint.incr
      waypoint.on_batch { |wp| logger.info waypoint.batch_line }
    end
    logger.info waypoint.final_line
  end

  def dump_to_ndj(filename)
    process = "dump to #{filename}"
    logger.info process
    waypoint = Waypoint.new(batch_size: 2_000_000, file_or_process: process)
    Zinzout.zout(filename) do |out|
      htid_history_hash.each_pair do |_, htidhist|
        out.puts htidhist.to_json
        waypoint.incr
        waypoint.on_batch { |wp| logger.info waypoint.batch_line }
      end
      recid_history_hash.each_pair do |_, recidhist|
        waypoint.incr
        waypoint.on_batch { |wp| logger.info waypoint.batch_line }
        out.puts recidhist.to_json
      end
    end
    logger.info waypoint.final_line
  end

  def self.new_from_ndj(filename, only_moved_htids: false)
    take_everything = !only_moved_htids
    hh              = self.new
    process         = "load #{filename}"
    hh.logger.info process
    waypoint = Waypoint.new(batch_size: 2_000_000, file_or_process: process)
    Zinzout.zin(filename).each do |line|
      histline = JSON.parse(line, create_additions: true)
      case histline
        when HTIDHistory
          hh.htids[histline.id] = histline if (take_everything or histline.moved?)
        when RecIDHistory
          hh.recids[histline.id] = histline
        else
          hh.logger.error "Weird class in new_from_ndj (#{histline.class})"
      end
      waypoint.incr
      waypoint.on_batch { |wp| hh.logger.info waypoint.batch_line }
    end
    hh.logger.info waypoint.final_line
    hh
  end

  def missing_htids
    htids = Set.new
    mrd   = most_recent_date
    @htid_history.each_pair do |htid, hist|
      htids << htid unless hist.most_recent_appearance == mrd
    end
    htids
  end

  def remove_missing_htids!
    missing = missing_htids
    missing.each { |mhtid| @htid_history.delete(mhtid) }
    @recid_history.each do |recid, hist|
      hist.appearances.reject! { |x| missing.include? hist.id }
    end
    self
  end

  def most_recent_date
    dts = Set.new
    @htid_history.each_pair do |htid, hist|
      dts << hist.most_recent_appearance
    end
    dts.max
  end

  def redirects
    yyyymm             = most_recent_date
    redirects          = {}
    not_redirects = Set.new

    htids.each_pair do |htid, htid_history|
      next unless htid_history.moved?

      current_record = current_record(htid)

      # If the most recent record doesn't exist in the latest dump,
      # we're certainly not going to redirect to it, so we just
      # move on.

      if current_record.most_recent_appearance != yyyymm
        logger.warn "Got a dead-end for #{htid} dying out at record #{current_record.id}, last seen on #{current_record.most_recent_appearance}"
        next
      end

      # Which HTIDs are currently on the same record as this one?
      current_record_htids = current_record.htids

      # For each record this HTID _used_ to be on, see if all those HTIDs moved to the
      # same place. If so, print out a redirect
      #
      htid_history.rec_ids.each do |recid|
        next if not_redirects.include?(recid)

        record_history = recid_history(recid)
        if record_history.most_recent_appearance == yyyymm # still exists
          not_redirects << recid
          next
        end

        # If all the HTIDs that were on this record are now on the same final-landing-place record,
        # we can create a redirect
        if record_history.ids.subset?(current_record_htids)
          redirects[recid] = current_record.id
          already_redirected << recid
        else
          redirects.delete(recid) # remove any incorrectly-added redirect
          not_redirects << recid
        end
      end
    end
    redirects
  end

  private

  def intify(str)
    str.gsub!(LEADING_ZEROS, EMPTY)
    str.to_i
  end

end
