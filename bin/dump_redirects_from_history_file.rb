# frozen_string_literal: true

require 'pathname'
here = Pathname.new(__dir__)
libdir = here.parent + 'lib'
$LOAD_PATH.unshift libdir
require 'date'
require 'logger'
require 'hathifile_history'


STDOUT.sync = true
LOGGER = Logger.new(STDOUT)

ndj_file = ARGV.shift
redirects_file= ARGV.shift

LOGGER.info "Starting load of #{ndj_file}"
recs = HathifileHistory::Records.load_from_ndj(ndj_file)

LOGGER.info "Compute current record contents"
recs.compute_current_sets!(recs.newest_load)

LOGGER.info "Remove missing HTIDs before further analysis"
recs.remove_dead_htids!

LOGGER.info "Dump redirects to #{redirects_file}"
Zinzout.zout(redirects_file) do |out|
  recs.redirects.each_pair do |source, sink|
    out.puts "%09d\t%09d" % [source, sink]
  end
end


