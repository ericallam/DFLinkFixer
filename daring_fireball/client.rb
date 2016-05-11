# frozen_string_literal: true
require 'nokogiri'
require 'open-uri'

module DaringFireball
  class Client
    class ArchivePage
      attr_reader :url

      def initialize(url:)
        self.url = url
      end

      def to_file_name
        parts = url.split('/').reverse

        [parts[1], parts.first].join("-")
      end

      protected

      attr_writer :url
    end

    class LinkedListItem
      attr_reader :url
      attr_reader :daring_fireball_url
      attr_reader :title

      def initialize(url:, daring_fireball_url:, title:)
        self.url = url
        self.daring_fireball_url = daring_fireball_url
        self.title = title
      end

      protected

      attr_writer :url
      attr_writer :daring_fireball_url
      attr_writer :title
    end

    LINKED_LIST_BASE_URI = 'http://daringfireball.net/linked/'

    def each_archive_page(&block)
      find_all_archive_pages.each(&block)
    end

    def each_linked_list_item_on_archive_page(archive_url, &block)
      parse_linked_list_items(archive_url).each(&block)
    end

    def fetch_linked_list_item(archive_url)
      yield parse_single_item(archive_url)
    end

    protected

    def find_all_archive_pages
      linked_list_doc = Nokogiri::HTML(open(LINKED_LIST_BASE_URI))
      archive_page_links = linked_list_doc.xpath(%(//*[@id="Main"]/div[3]/ul/li/a))
      archive_page_links.map do |link|
        ArchivePage.new(url: link['href'])
      end
    end

    def parse_linked_list_items(archive_url)
      archive_doc = Nokogiri::HTML(open(archive_url))
      archive_doc.xpath(%(//*[@id="Main"]/dl/dt)).map do |element|
        url = element.at_css('a')['href']
        daring_fireball_url = element.css('a.permalink').first['href']
        title = element.at_css('a').text

        LinkedListItem.new(
          url: url,
          daring_fireball_url: daring_fireball_url,
          title: title
        )
      end
    end

    def parse_single_item(archive_url)
      archive_doc = Nokogiri::HTML(open(archive_url))
      element = archive_doc.xpath(%(//*[@id="Main"]/dl/dt/a)).first

      url = element['href']
      title = element.text

      LinkedListItem.new(
        url: url,
        daring_fireball_url: archive_url,
        title: title
      )
    end
  end
end
