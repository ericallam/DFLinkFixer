# frozen_string_literal: true
require 'uri'
require 'cgi'

module URI
  class << self

    def parse_with_safety(uri)
      invalid_characters_regex = %r/([{}|\^\[\]`])/

      parse_without_safety(uri.gsub(invalid_characters_regex) { |s| CGI.escape(s) })
    end

    alias parse_without_safety parse
    alias parse parse_with_safety
  end
end
