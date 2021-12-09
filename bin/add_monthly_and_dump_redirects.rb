# frozen_string_literal: true

require 'pathname'
here = Pathname.new(__dir__)
libdir = here.parent + 'lib'
$LOAD_PATH.unshift libdir
root = here.parent
require 'date'
require 'logger'
require 'hathifile_history'

STDOUT.sync = true
LOGGER      = Logger.new(STDOUT)

hathifile        = ARGV.shift
old_history_file = ARGV.shift # optional
new_history_file = ARGV.shift # optional
redirects_file   = ARGV.shift # also optional

yyyymm      ||= HathifileHistory::Records.yyyymm_from_filename(hathifile)
yyyymm      = Integer(yyyymm)
yyyy        = yyyymm.to_s[0..3]
mm          = yyyymm.to_s[4..5]
last_month  = DateTime.parse("#{yyyy}-#{mm}-01").prev_month
last_yyyymm = last_month.strftime '%Y%m'

old_history_file ||= root + "history_files" + "#{last_yyyymm}.ndj.gz"
new_history_file ||= root + "history_files" + "#{yyyymm}.ndj.gz"
redirects_file   ||= root + "redirects" + "redirects_#{yyyymm}.txt"

unless File.exist?(old_history_file)
  LOGGER.error "Can't find #{old_history_file} for loading historical data. Aborting."
  exit 1
end

if File.exist?(new_history_file)
  LOGGER.error "#{new_history_file} already exists. Rename/delete it first"
  exit 1
end

# Get the old stuff
recs = HathifileHistory::Records.load_from_ndj(old_history_file)

# Add the new stuff
recs.add_monthly(hathifile)

# ...and dump it out again
recs.dump_to_ndj(new_history_file)

LOGGER.info "Compute htid -> current_record"
recs.compute_current_sets!(recs.newest_load)

LOGGER.info "Remove missing HTIDs before further analysis"
recs.remove_dead_htids!

LOGGER.info "Dump redirects to #{redirects_file}"
Zinzout.zout(redirects_file) do |out|
  recs.redirects.each_pair do |source, sink|
    out.puts "%09d\t%09d" % [source, sink]
  end
end



