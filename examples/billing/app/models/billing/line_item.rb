module Billing
  class LineItem < ApplicationRecord
    include Auditable
    extend Searchable
  end
end
