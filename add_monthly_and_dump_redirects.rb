# frozen_string_literal: true

$LOAD_PATH.unshift 'lib'
require 'pathname'
require 'date'
require 'logger'
load 'rec_only_test.rb'


STDOUT.sync = true
LOGGER = Logger.new(STDOUT)

here = Pathname.new(__dir__)

infile = ARGV.shift
outfile = ARGV.shift # optional

yyyymm ||= Records.yyyymm_from_filename(infile)
yyyymm = Integer(yyyymm)

outfile ||= here + "history_files" + "#{yyyymm}.ndj.gz"

yyyy = yyyymm.to_s[0..3]
mm = yyyymm.to_s[4..5]

last_month = DateTime.parse("#{yyyy}-#{mm}-01").prev_month
last_yyyymm = last_month.strftime '%Y%m'

load_file = here + "history_files" + "#{last_yyyymm}.ndj.gz"
redirects_file = here + "redirects" + "redirects_#{yyyymm}.txt"

if !File.exists?(load_file)
  STDERR.puts "Can't find #{load_file} for loading historical data. Aborting."
  exit 1
end

if File.exists?(outfile)
  STDERR.puts "#{outfile} already exists. Rename/delete it first"
  exit 1
end


# Get the old stuff
recs = Records.load_from_ndj(load_file)

# Add the new stuff
recs.add_monthly(infile)

# ...and dump it out again
hh.dump_to_ndj(outfile)

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



