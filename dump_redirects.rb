# frozen_string_literal: true

$LOAD_PATH.unshift 'lib'
require 'pathname'
require 'date'
require 'logger'
load 'rec_only_test.rb'

STDOUT.sync = true
LOGGER = Logger.new(STDOUT)

ndj_file = ARGV.shift
redirects_file= ARGV.shift

LOGGER.info "Starting load of #{ndj_file}"
recs = Records.load_from_ndj(ndj_file)

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


