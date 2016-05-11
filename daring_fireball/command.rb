# frozen_string_literal: true

require_relative './client'
require_relative './web_archive'
require_relative './availability'

require 'csv'

module DaringFireball
  class Command
    module OutputFormatters
      def self.fetch_outputter(outputter)
        case outputter.to_s
        when 'stdout'
          StdoutFormatter.new
        when 'csv'
          CSVFormatter.new
        else
          raise StandardError, "Could not find outputter for #{outputter}"
        end
      end

      class CSVFormatter
        def output_available(linked_list:)
          @csv << ["Reachable", linked_list.daring_fireball_url, linked_list.url, linked_list.title, nil, nil, nil, "200"]
        end

        def output_redirect(linked_list:, redirect:)
          @csv << ["Redirected", linked_list.daring_fireball_url, linked_list.url, linked_list.title, nil, redirect, nil, nil]
        end

        def output_too_many_redirects(linked_list:, last_url:, count:)
          @csv << ["Too Many Redirects", linked_list.daring_fireball_url, linked_list.url, linked_list.title, nil, last_url, count, nil]
        end

        def output_server_problem(linked_list:, status_code:, entry: nil)
          @csv << ["Server Problem", linked_list.daring_fireball_url, linked_list.url, linked_list.title, entry&.url, nil, nil, status_code]
        end

        def output_connection_problem(linked_list:, message:, entry: nil)
          @csv << ["Connection Problem", linked_list.daring_fireball_url, linked_list.url, linked_list.title, entry&.url, nil, nil, nil]
        end

        def start!(options = {})
          io = options[:io] || $stdout

          @csv = CSV.new(io)
          @csv << ["Result", "DF URL", "Original URL", "Title", "Last Valid Web Archive URL", "Redirect URL", "Redirect Count", "Response Code"]
        end

        def finish!(options = {})
        end

        def to_file_name(archive_page)
          "#{archive_page.to_file_name}.csv"
        end
      end

      class StdoutFormatter
        def output_available(linked_list:)
          $stdout.puts "[#{linked_list.daring_fireball_url}] Found #{linked_list.url}. Link is still good!"
        end

        def output_redirect(linked_list:, redirect:)
          $stdout.puts "[#{linked_list.daring_fireball_url}] Linked list item redirected #{linked_list.url} -> #{redirect}"
        end

        def output_too_many_redirects(linked_list:, last_url:, count:)
          $stdout.puts "[#{linked_list.daring_fireball_url}] Linked list item redirected too many (#{count}) times #{linked_list.url} -> #{last_url}"
        end

        def output_server_problem(linked_list:, status_code:, entry: nil)
          if entry.nil?
            $stdout.puts "[#{linked_list.daring_fireball_url}] Could not connect to #{linked_list.url}. Code #{status_code}"
          else
            $stdout.puts "[#{linked_list.daring_fireball_url}] Could not connect to #{linked_list.url}. Code #{status_code}. Last Valid Web Archive URL is #{entry.url}"
          end
        end

        def output_connection_problem(linked_list:, message:, entry: nil)
          if entry.nil?
            $stdout.puts "[#{linked_list.daring_fireball_url}] Could not connect to #{linked_list.url}. #{message}"
          else
            $stdout.puts "[#{linked_list.daring_fireball_url}] Could not connect to #{linked_list.url}. #{message}. Last Valid Web Archive URL is #{entry.url}"
          end
        end

        def start!(options = {})
        end

        def finish!(options = {})
        end
      end
    end

    attr_reader :formatter, :client, :options

    def initialize(options = {})
      self.options = options
      self.formatter = OutputFormatters.fetch_outputter(options[:output])
      self.client = Client.new
    end

    def perform!
      if options[:url]
        formatter.start!(options)

        client.fetch_linked_list_item(options[:url]) do |linked_list|
          output_linked_list(linked_list)
        end

        formatter.finish!(options)
      elsif options[:archive]
        formatter.start!(options)

        client.each_linked_list_item_on_archive_page(options[:archive]) do |linked_list|
          output_linked_list(linked_list)
        end

        formatter.finish!(options)
      else
        output_dir = File.join(Dir.pwd, 'output')
        FileUtils.mkdir_p(output_dir)

        client.each_archive_page do |archive_page|
          file_path = File.join(output_dir, formatter.to_file_name(archive_page))

          next if File.exist?(file_path)

          formatter.start!(io: File.new(file_path, 'w+'))
          client.each_linked_list_item_on_archive_page(archive_page.url) do |linked_list|
            output_linked_list(linked_list)
          end
          formatter.finish!(options)
        end
      end
    end

    protected

    attr_writer :formatter, :client, :options

    def output_linked_list(linked_list)
      availability = Availability.new(url: linked_list.url)
      response = availability.request

      case response
      when Availability::Available
        formatter.output_available(
          linked_list: linked_list
        )
      when Availability::Redirect
        formatter.output_redirect(
          linked_list: linked_list,
          redirect: response.uri
        )
      when Availability::TooManyRedirects
        formatter.output_too_many_redirects(
          linked_list: linked_list,
          last_url: response.uri,
          count: response.count,
        )
      when Availability::ServerProblem
        web_archive = WebArchive.new(url: linked_list.url)
        entry = web_archive.first_valid_entry

        formatter.output_server_problem(
          linked_list: linked_list,
          status_code: response.status_code,
          entry: entry,
        )
      when Availability::ConnectionProblem
        web_archive = WebArchive.new(url: linked_list.url)
        entry = web_archive.first_valid_entry

        formatter.output_connection_problem(
          linked_list: linked_list,
          message: response.message,
          entry: entry,
        )
      else
        raise StandardError, "Could not handle availability response #{response.class}"
      end
    end
  end
end
