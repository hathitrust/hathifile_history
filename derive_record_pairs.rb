# frozen_string_literal: true

$LOAD_PATH.unshift 'lib'

require 'waypoint'
require 'hathifile_history'

filename = ARGV.shift
yyyymm   = Integer(ARGV.shift) # "Now" -- the last month loaded
outfile  = ARGV.shift

# Given a hathifile_history .ndj.gz file that has the deleted HTIDs
# already removed, figure out which record IDs should map to others.
#
# Given an HTID that has ever moved, with a record history:
#   htid_1 => [recid_1, YYYYMM_1], [recid_2, YYYYMM_2], ..., [recid_N, YYYYMM_N]
#
# * Find the recid_Now with the most-recent date. This is the record the HTID currently lives on
# * Get a list, htids_Now, of all the HTIDs that current live on recid_Now
# * For every _other_ recid_X this HTID has ever lived on:
#   * Get a list htids_X of all the HTIDs ever associated with recid_X
#   * See if htids_X is a subset of htids_Now

# We only need the HTIDs that have ever moved, since they tell us which records
# to look at.

hh = HathifileHistory.new_from_ndj(filename, only_moved_htids: true)
# # Dump it 'cause you know the code below has bugs...
# hh.dump_to_ndj('only_moved.ndj.gz')
# hh = HathifileHistory.new_from_ndj('only_moved.ndj.gz', only_moved_htids: true)

hhh = hh.htid_history_hash
rhh = hh.recid_history_hash

require 'logger'
LOGGER = Logger.new(STDOUT)

sswp = Waypoint.new(batch_size: 100_000, file_or_process: "Subset checks")
htwp = Waypoint.new(batch_size: 50_000, file_or_process: "HTIDs checked")
File.open(outfile, 'w:utf-8') do |out|
  hhh.each_pair do |htid, hist|
    appearances   = hist.appearances.sort { |a, b| a.dt <=> b.dt }
    current_recid = appearances.pop.id

    if appearances.empty? # shouldn't happen if we only get moved htids
      LOGGER.warn "Only one appearance for #{htid}; weird"
      next
    end

    # If the current_recid is no longer in our rhh hash, it's already been
    # determined to be part of an ineligible chain, and we can move on

    if !rhh.has_key?(current_recid)
      LOGGER.warn "#{current_recid} not found in rhh set."
      next
    end

    # Which HTIDs are currently on the same record as this one?

    current_recid_htids = rhh[current_recid].htids

    # For each record this HTID _used_ to be on, see if all those HTIDs moved to the
    # same place. If so, print out a redirect
    #
    appearances.map(&:id).each do |recid|
      next unless rhh.has_key?(recid) # not there

      next if rhh[recid].most_recent_appearance == yyyymm # still exists

      # If all the HTIDs that were on this record are now on the same final-landing-place record,
      # we can create a redirect
      if rhh[recid].ids.subset?(current_recid_htids)
        out.puts "#{recid}\t#{current_recid}"
      end
      sswp.incr
      sswp.on_batch { LOGGER.info sswp.batch_line }
    end

    htwp.incr
    htwp.on_batch { LOGGER.info htwp.batch_line}
  end
end

LOGGER.info htwp.final_line
LOGGER.info sswp.final_line

