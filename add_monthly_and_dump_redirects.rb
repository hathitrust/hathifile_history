# frozen_string_literal: true

$LOAD_PATH.unshift 'lib'
require 'pathname'
require 'date'
require 'hathifile_history'
require 'logger'


STDOUT.sync = true

LOGGER = Logger.new(STDOUT)

here = Pathname.new(__dir__)

infile = ARGV.shift
outfile = ARGV.shift

yyyymm ||= HathifileHistory.yyyymm_from_filename(infile)
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

hh = HathifileHistory.new_from_ndj(load_file)
hh.add_monthly(infile)
hh.dump_to_ndj(outfile)

LOGGER.info "Remove missing HTIDs before further analysis"
hh.remove_missing_htids!

LOGGER.info "Derive and dump redirect pairs to #{redirects_file}"
File.open(redirects_file, 'w') do |out|
  hh.redirects.each_pair do |source, sink|
    out.puts "#{source}\t#{sink}"
  end
end



