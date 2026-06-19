module Billing
  class Invoice < ApplicationRecord
    include Auditable
    prepend Tracked
    extend Searchable
  end
end
