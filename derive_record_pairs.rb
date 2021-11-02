# frozen_string_literal: true

$LOAD_PATH.unshift 'lib'

require 'waypoint'
require 'hathifile_history'

STDOUT.sync = true

filename = ARGV.shift
# yyyymm   = Integer(ARGV.shift) # "Now" -- the last month loaded
outfile = ARGV.shift

# Given a hathifile_history .ndj.gz file that has the deleted HTIDs
# already removed, figure out which record IDs should map to others.
#
# Basically, if every HTID that has ever lived on a given record now lives on a different
# record, create a redirect.
#
# Given an HTID that has ever moved, with a record history:
#   htid_1 => [recid_1, YYYYMM_1], [recid_2, YYYYMM_2], ..., [recid_N, YYYYMM_N]
#
# * Find the recid_Now with the most-recent date. This is the record the HTID currently lives on
#   - if that record is no longer live, we're not going to redirect to it, so move on
# * Get a list, htids_Now, of all the HTIDs that current live on recid_Now
# * For every _other_ recid_X this HTID has ever lived on:
#   * Get a list htids_X of all the HTIDs ever associated with recid_X
#   * See if htids_X is a subset of htids_Now

# We focus on the HTIDs that have ever moved, since they tell us which records
# to bother to look at.

hh = HathifileHistory.new_from_ndj(filename, only_moved_htids: true)

require 'logger'
LOGGER = Logger.new(STDOUT)

sswp = Waypoint.new(batch_size: 100_000, file_or_process: "Subset checks")
htwp = Waypoint.new(batch_size: 50_000, file_or_process: "HTIDs checked")

# # Dump it 'cause you know the code below has bugs...
# hh.dump_to_ndj('only_moved.ndj.gz')
# hh = HathifileHistory.new_from_ndj('only_moved.ndj.gz', only_moved_htids: true)
#
yyyymm = hh.most_recent_date

LOGGER.info "Identifying and removing dead HTIDs (not appearing in #{yyyymm})"
hh.remove_missing_htids!

already_redirected = Set.new
redirects          = {}

File.open(outfile, 'w:utf-8') do |out|

  hh.htids.each_pair do |htid, htid_history|
    appearances    = htid_history.appearances.sort { |a, b| a.dt <=> b.dt }
    current_record = hh.current_record(htid)

    # If the most recent record doesn't exist in the latest dump,
    # we're certainly not going to redirect to it, so we just
    # move on.

    if current_record.most_recent_appearance != yyyymm
      LOGGER.warn "Got a dead-end for #{htid} dying out at record #{current_record.id}, last seen on #{current_record.most_recent_appearance}"
      next
    end

    # Which HTIDs are currently on the same record as this one?

    current_record_htids = current_record.htids

    # For each record this HTID _used_ to be on, see if all those HTIDs moved to the
    # same place. If so, print out a redirect
    #
    htid_history.rec_ids.each do |recid|
      sswp.incr
      sswp.on_batch { LOGGER.info sswp.batch_line }

      next if already_redirected.include?(recid) # already dealt with

      record_history = hh.recid_history(recid)
      if record_history.most_recent_appearance == yyyymm # still exists
        next
      end

      # If all the HTIDs that were on this record are now on the same final-landing-place record,
      # we can create a redirect
      if record_history.ids.subset?(current_record_htids)
        redirects[recid] = current_record.id
        already_redirected << recid
      end

      htwp.incr
      htwp.on_batch { LOGGER.info htwp.batch_line }
    end
  end

  redirects.each_pair do |source, sink|
    out.puts "#{source}\t#{sink}"
  end
end

# Find any transitive relationships

overlap = Set.new(redirects.keys).intersection(Set.new(redirects.values))
unless overlap.empty?
  LOGGER.warn "Got overlaps of #{overlap.to_a.join(', ')}"
end

LOGGER.info htwp.final_line
LOGGER.info sswp.final_line

