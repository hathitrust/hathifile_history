require "bundler/setup"
require "pathname"
require "simplecov"
require "simplecov-lcov"

SimpleCov::Formatter::LcovFormatter.config do |c|
  c.report_with_single_file = true
  c.single_report_path = "coverage/lcov.info"
end
SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new([
  SimpleCov::Formatter::HTMLFormatter,
  SimpleCov::Formatter::LcovFormatter
])
SimpleCov.start do
  add_filter "/spec/"
end

require "hathifile_history"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

FIXTURES_DIR = Pathname.new(__dir__).realdirpath + "fixtures"

TEST_RECID = "000"
TEST_RECID_1 = "001"
TEST_BOGUS_RECID = "BOGUS"
TEST_HTID = "test.000"
TEST_HTID_1 = "test.001"
TEST_YYYYMM = 202301
TEST_EARLIER_YYYYMM = 202201
TEST_LATER_YYYYMM = 202401
TEST_VALID_HATHIFILE_NAME = "hathi_full_20230101.txt.gz"
TEST_NDJ_FILE = "test_dump.ndj.gz"
TEST_OLDER_SAMPLE_HATHIFILE_NAME = "sample_full_20220101.txt.gz"
TEST_SAMPLE_HATHIFILE_NAME = "sample_full_20230101.txt.gz"

class NullLogger < Logger
  def add(severity, message = nil, progname = nil)
  end
end
