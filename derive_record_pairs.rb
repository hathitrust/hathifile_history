# frozen_string_literal: true

$LOAD_PATH.unshift 'lib'

require 'waypoint'
require 'hathifile_history'

STDOUT.sync = true

infile = ARGV.shift
# yyyymm   = Integer(ARGV.shift) # "Now" -- the last month loaded
outfile = ARGV.shift

# Given a hathifile_history .ndj.gz file  figure out
# which record IDs should redirect to another.
#
# See the README.md for an explanation of the algorithm

Zinzout.zout(outfile) do |out|
  hh = HathifileHistory.new_from_ndj(infile, only_moved_htids: true)
  hh.redirects.each_pair do |source, sink|
    out.puts "#{source}\t#{sink}"
  end
end

