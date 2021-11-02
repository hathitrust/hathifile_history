# frozen_string_literal: true


class IDDate
  include Comparable
  attr_reader :id, :dt

  # @param [Integer] id The id of record or HTID, whatever's needed
  # @param [Integer] dt The date as YYYYMM (just year/month for our purposes)
  def initialize(id, dt)
    @dt    = dt
    @id = id
    @json_create_id = JSON.create_id.freeze
    @classname = self.class.name.freeze
  rescue => e
    STDERR.puts "#{id}/#{dt}: #{e}"
  end


  def <=>(other)
    @id <=> other.id and @dt <=> other.dt
  end

  def to_h
    { id: @id, dt: @dt }
  end


  def to_json(*args)
    { id: @id, dt: @dt, @json_create_id => @classname}.to_json(*args)
  end

  def self.json_create(obj)
    self.new(obj['id'], obj['dt'])
  end

end
