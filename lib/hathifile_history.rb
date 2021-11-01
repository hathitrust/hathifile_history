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

  def add_monthly(filename)
    fulldate     = filename.gsub(/\D/, '')
    yearmonth    = fulldate[0..-3].to_i
    cnt          = 0
    process_name = "add from #{filename}"
    logger.info process_name
    waypoint = Waypoint.new(batch_size: 1_000_000, file_or_process: process_name)
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
    waypoint = Waypoint.new(batch_size: 1_000_000, file_or_process: process )
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
    hh       = self.new
    process = "load #{filename}"
    hh.logger.info process
    waypoint = Waypoint.new(batch_size: 1_000_000, file_or_process: process)
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

  private

  def intify(str)
    str.gsub!(LEADING_ZEROS, EMPTY)
    str.to_i
  end

end
