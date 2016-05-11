# frozen_string_literal: true
require 'json'
require 'open-uri'
require 'cgi'

module DaringFireball
  class WebArchive
    class WebArchiveEntry
      attr_reader :urlkey, :timestamp, :original, :mimetype, :statuscode, :digest, :length

      def initialize(urlkey:, timestamp:, original:, mimetype:, statuscode:, digest:, length:)
        self.urlkey = urlkey
        self.timestamp = timestamp
        self.original = original
        self.mimetype = mimetype
        self.statuscode = statuscode
        self.digest = digest
        self.length = length
      end

      def valid?
        statuscode == "200"
      end

      def url
        File.join("http://web.archive.org/web", timestamp, original)
      end

      protected

      attr_writer :urlkey, :timestamp, :original, :mimetype, :statuscode, :digest, :length
    end
    class Client
      def initialize(url)
        self.url = url
      end

      def web_archive_entries
        @web_archive_entries ||= begin
          columns = json.shift

          return [] if columns.nil?

          columns = columns.map &:to_sym

          json.map do |row|
            attributes = Hash[columns.zip(row)]

            WebArchiveEntry.new(**attributes)
          end
        end
      rescue OpenURI::HTTPError
        []
      end

      protected

      attr_accessor :url

      def json
        @json ||= JSON.parse(open(request_url).read)
      end

      def request_url
        url_without_scheme = url.gsub(/^https?\:\/\//, '')
        escaped_url = CGI.escape(url_without_scheme)

        "http://web.archive.org/cdx/search/cdx?url=#{escaped_url}&output=json"
      end
    end

    attr_reader :url

    def initialize(url:)
      self.url = url
    end

    def last_valid_entry
      web_archive_entries.select(&:valid?).last
    end

    def first_valid_entry
      web_archive_entries.select(&:valid?).first
    end

    def web_archive_entries
      client.web_archive_entries
    end

    protected

    attr_writer :url

    def client
      @client ||= Client.new(url)
    end

  end
end
