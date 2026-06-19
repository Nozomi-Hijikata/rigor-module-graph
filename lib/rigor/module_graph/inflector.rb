# frozen_string_literal: true

module Rigor
  module ModuleGraph
    # Minimal Rails-style inflection helpers. Used to infer a class
    # name from a Rails association argument (+has_many :invoices+
    # → +Invoice+).
    #
    # Deliberately tiny — we don't ship +ActiveSupport::Inflector+
    # and its irregular-noun table; the plugin records its guess
    # at +confidence: "syntax"+ so a downstream reviewer can spot
    # mis-singularised plurals in the graph. Apps that need exact
    # association class names should rely on +class_name:+ overrides
    # in the source, which the Analyzer reads verbatim.
    module Inflector
      module_function

      IRREGULAR_PLURALS = {
        "people" => "person",
        "men" => "man",
        "women" => "woman",
        "children" => "child",
        "feet" => "foot",
        "teeth" => "tooth",
        "geese" => "goose",
        "mice" => "mouse",
        "lice" => "louse"
      }.freeze

      # @param word [String]
      # @return [String] best-effort singular form
      def singularize(word)
        downcased = word.downcase
        return word.dup if word.empty?
        return preserve_case(IRREGULAR_PLURALS[downcased], word) if IRREGULAR_PLURALS.key?(downcased)
        return word[0..-4] + "y" if word =~ /ies\z/i && word.size > 3
        return word[0..-3] if word =~ /ses\z/i  # buses → bus, classes → clas... we accept loss
        return word[0..-2] if word.end_with?("s") && !word.end_with?("ss")

        word.dup
      end

      # +"foo_bar_baz" → "FooBarBaz"+. Plain Rails camelize without
      # acronym handling.
      def camelize(word)
        word.to_s.split("_").map { |seg| seg.empty? ? seg : seg[0].upcase + seg[1..] }.join
      end

      # +"invoices" → "Invoice"+ — the common Rails association
      # argument to class-name path.
      def class_name_for(symbol_or_string)
        camelize(singularize(symbol_or_string.to_s))
      end

      def preserve_case(replacement, original)
        # The irregular table is lower-case; preserve a leading
        # capital from the source so +People+ → +Person+.
        return replacement.capitalize if original[0] =~ /[A-Z]/

        replacement.dup
      end
    end
  end
end
