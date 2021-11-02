# frozen_string_literal: true

require 'set'
require 'json'
require_relative 'id_date'

class GenericHistory

  attr_reader :id, :appearances
  attr_accessor :most_recent_appearance

  def initialize(id)
    @id                     = id.freeze
    @most_recent_appearance = 0
    @appearances            = []
    @id_set                 = Set.new

    @json_create_id = JSON.create_id.freeze
    @classname      = self.class.name.freeze
  end

  # @param [IDDate] iddate
  def add(iddate)
    unless @id_set.include? iddate.id
      @appearances << iddate
      @id_set.add iddate.id
    end
    @most_recent_appearance = [most_recent_appearance, iddate.dt].max
  end

  def ids
    @id_set
  end

  def to_h(opts = {}.freeze)
    { id:                     @id,
      most_recent_appearance: @most_recent_appearance,
      appearances:            @appearances.map(&:to_h),
    }
  end

  def to_json(*args)
    {
      id:                     @id,
      most_recent_appearance: @most_recent_appearance,
      appearances:            @appearances,
      @json_create_id         => @classname
    }.to_json(*args)
  rescue => e
    require 'pry'; binding.pry
  end


  def self.json_create(obj)
    n = self.new(obj['id'.freeze])
    obj['appearances'.freeze].each do |rnd|
      n.add(rnd)
    end
    n.most_recent_appearance = obj['most_recent_appearance'.freeze]
    n
  rescue => e
    puts "ERROR #{e} with "
    pp obj
  end

end