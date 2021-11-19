$:.unshift 'lib'
load 'rec_only_test.rb'
require 'date'

STDOUT.sync = true

hh = Records.new

# Need to start from a mid-point? Load up the latest version here
# hh = HathifileHistory.new_from_ndj('history_files/202108.ndj.gz')

current_year_str = DateTime.now.year.to_s

last_good_history_file = ''
('2008'..current_year_str).each do |year|
  ('01'..'12').each do |month|
    yearmonth = "#{year}#{month}"

    # Big problems with file from 200812 so skip it
    next if yearmonth == "200812"

    filename     = "../archive/hathi_full_#{yearmonth}01.txt.gz"
    history_file = "history_files/#{yearmonth}.ndj.gz"

    if !File.exists?(filename)
      puts "Can't find #{filename}; skipping it"
      next
    end

    last_good_history_file = history_file
    hh.add_monthly(filename)

    # Dump periodically in case things go haywire
    if month == "12"
      hh.dump_to_ndj(last_good_history_file)
    end
  end
end

# Final one

hh.dump_to_ndj(last_good_history_file)

