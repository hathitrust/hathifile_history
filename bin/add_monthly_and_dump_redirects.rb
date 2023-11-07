# frozen_string_literal: true

require 'pathname'
here = Pathname.new(__dir__)
libdir = here.parent + 'lib'
$LOAD_PATH.unshift libdir
root = here.parent
require 'date'
require 'date_named_file'
require 'logger'
require 'hathifile_history'

STDOUT.sync = true
LOGGER      = Logger.new(STDOUT)

def usage
  $stderr.puts %Q{
Build up the latest history file and compue a new catalog redirects file.

If given no arguments, will find the latest full file in /.../archive/,
compute all the other input/output files based on the date embedded in that
name, and run it all. If the previous history file is missing, or the 
target redirects file already exists, an error will be thrown and the
process aborted.

Optionally takes 1-4 arguments, in this order. Anything not given will be computed
(e.g., if only one argument is given, it's assumed to be the new hathifile and 
everything else will be derived from that). 

  * the newest hathifile to index
  * the previous history file on which to base the computation
  * the target name of the new history file
  * the target name of the new redirects file

}
  exit 1
end

hathifile        = ARGV.shift # optional; assumes last one
old_history_file = ARGV.shift # optional; assumes previous month
new_history_file = ARGV.shift # optional; will create based on infile name
redirects_file   = ARGV.shift # optional; will create based on infile name

if hathifile == '-h'
  usage
end

if hathifile.nil?
  hathifile = DateNamedFile.new('hathi_full_%Y%m%d.txt.gz').in_dir('../archive').last.to_s
  LOGGER.info "No input file given. Using #{hathifile}"  
end

yyyymm      ||= HathifileHistory::Records.yyyymm_from_filename(hathifile)
yyyymm      = Integer(yyyymm)
yyyy        = yyyymm.to_s[0..3]
mm          = yyyymm.to_s[4..5]
last_month  = DateTime.parse("#{yyyy}-#{mm}-01").prev_month
last_yyyymm = last_month.strftime '%Y%m'

old_history_file ||= root + "history_files" + "#{last_yyyymm}.ndj.gz"
new_history_file ||= root + "history_files" + "#{yyyymm}.ndj.gz"
redirects_file   ||= root + "redirects" + "redirects_#{yyyymm}.txt.gz"

unless File.exist?(old_history_file)
  LOGGER.error "Can't find #{old_history_file} for loading historical data. Aborting."
  exit 1
end

if File.exist?(new_history_file)
  LOGGER.error "#{new_history_file} already exists. Rename/delete it first"
  exit 1
end

LOGGER.info "Will read from #{old_history_file}"
LOGGER.info "Will write to #{new_history_file} and create #{redirects_file}"

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
LOGGER.info "All done!"



