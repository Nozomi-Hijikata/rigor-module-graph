module Billing
  class Invoice < ApplicationRecord
    include Auditable
    include Discountable
    prepend Tracked
    extend Searchable
  end
end
