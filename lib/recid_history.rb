# frozen_string_literal: true

require_relative 'generic_history'
require_relative 'id_date'

class RecIDHistory < GenericHistory

  alias_method :htids, :ids

end