module Billing
  class Customer < ApplicationRecord
    include Auditable

    has_many :invoices
    has_one :address
    belongs_to :tenant
    has_and_belongs_to_many :tags

    attr_accessor :preferred_language

    def display_name
      "#{name} <#{email}>"
    end

    private

    def normalize_email
      email.downcase
    end
  end
end
