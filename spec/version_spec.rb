# frozen_string_literal: true

RSpec.describe HathifileHistory do
  it "has a version stting" do
    expect(HathifileHistory::VERSION).to match(/\d+\.\d+\.\d+/)
  end
end
