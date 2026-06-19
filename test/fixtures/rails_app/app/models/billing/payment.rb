module Billing
  class Payment < ApplicationRecord
    include Auditable
  end
end
