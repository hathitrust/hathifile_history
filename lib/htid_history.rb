# frozen_string_literal: true

require 'json'
require_relative 'id_date'
require_relative 'generic_history'

class HTIDHistory < GenericHistory

  alias_method :rec_ids, :ids
  alias_method :recids, :ids

  def moved?
    appearances.size > 1
  end

end