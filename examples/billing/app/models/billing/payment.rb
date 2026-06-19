module Billing
  class Payment < ApplicationRecord
    include Auditable
    prepend Tracked
  end
end
