# frozen_string_literal: true

$:.unshift 'lib'
require 'hathifile_history'
require 'set'

filename = ARGV.shift
target_date = Integer(ARGV.shift)
outfile = ARGV.shift

hh = HathifileHistory.new_from_ndj(filename)

missing_ids = Set.new
htids = hh.htid_history_hash
recids = hh.recid_history_hash

htids.each_pair do |htid, hist|
  if hist.most_recent_appearance < target_date
    missing_ids << htid
    htids.delete(htid)
  end
end

# Now go through all the records and scrub those IDs from them.
# The ID sets will remain incorrect, but they get recreated during
# a dump/load cycle so we don't really care
#
# If we've got nothing left, delete the record as well. 

recids.each_pair do |recid, hist|
  hist.appearances.delete_if{|x| missing_ids.include?(x.id)}
  if hist.appearances.empty?
    recids.delete(recid)
  end
end

hh.dump_to_ndj(outfile)


