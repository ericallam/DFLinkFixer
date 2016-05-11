# frozen_string_literal: true
require_relative './monkey_patch_uri'
require 'net/https'
require 'json'
require 'shellwords'

module DaringFireball
  class Availability
    class TooManyRedirectsError < StandardError
      attr_reader :url, :redirects

      def initialize(url, redirects)
        @url = url
        @redirects = redirects
      end
    end

    class Base
      def initialize(response: nil)
        @response = response
      end
    end

    class Available < Base
    end

    class Redirect < Base
      def uri
        @response.uri
      end
    end

    class TooManyRedirects < Base
      def initialize(error:, **options)
        self.error = error
        super **options
      end

      def uri
        error.url
      end

      def count
        error.redirects
      end

      protected

      attr_accessor :error
    end

    class ServerProblem < Base
      def initialize(error:, **options)
        self.error = error
        super **options
      end

      def status_code
        error.response.code.to_i
      end

      protected

      attr_accessor :error
    end

    class ConnectionProblem < Base
      def initialize(error:, **options)
        self.error = error
        super **options
      end

      def message
        error.message
      end

      protected

      attr_accessor :error
    end

    class PhantomRequest
      attr_reader :url

      def initialize(url)
        self.url = url
      end

      def response
        @response ||= execute_request
      end

      protected

      attr_writer :url

      def execute_request
        JSON.parse(%x(#{shell_string}))
      end

      def shell_string
        path_to_phantom = File.join(project_root, "bin", "phantomjs")
        path_to_config = File.join(project_root, "daring_fireball", "scripts", "config.json")
        path_to_script = File.join(project_root, "daring_fireball", "scripts", "request.js")

        %{#{path_to_phantom} --config=#{path_to_config} #{path_to_script} %s} % Shellwords.escape(url)
      end

      def project_root
        Dir.pwd
      end
    end

    class Request
      attr_reader :url

      def initialize(url)
        self.url = url
      end

      def response
        @response ||= http.request(request)
      end

      protected

      attr_writer :url

      def request
        @req ||= begin
          request = Net::HTTP::Get.new(uri, 'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_4) AppleWebKit/602.1.29 (KHTML, like Gecko) Version/9.1.1 Safari/601.6.17')

          if uri.host.include?('linkedin.com')
            request.add_field "Cookie", "JSESSIONID=\"ajax:4504012775649973114\"; bcookie=\"v=2&3a7d2ee9-ed59-4da5-8ead-9c057c301775\"; bscookie=\"v=1&20160510210845f6f6fc50-af0c-40bf-86da-56cbc64d909aAQGMfKPgd5YqyuuAd81yPphpbuMDADkk\"; lidc=\"b=TGST01:g=89:u=1:i=1462914525:t=1463000925:s=AQGQGr3bk1Xqu8dM07P9Trufbtova-Fo\""
          end

          request
        end
      end

      def http
        @http ||= begin
          http = Net::HTTP.new(uri.host, uri.port)

          if uri.scheme == "https"
            http.use_ssl = true
            http.verify_mode = OpenSSL::SSL::VERIFY_NONE
          end

          http
        end
      end

      def uri
        @uri ||= URI(url)
      end
    end

    attr_reader :url, :error

    def initialize(url:)
      self.url = url
    end

    def request
      response = make_request(url: url)

      if response.uri.to_s == URI(url).to_s
        Available.new(response: response)
      else
        Redirect.new(response: response)
      end
    rescue TooManyRedirectsError => e
      TooManyRedirects.new(error: e, response: response)
    rescue Net::HTTPServerException => e
      ServerProblem.new(error: e)
    rescue Net::HTTPFatalError => e
      ServerProblem.new(error: e)
    rescue Net::OpenTimeout => e
      ConnectionProblem.new(error: e)
    rescue SocketError => e
      ConnectionProblem.new(error: e)
    rescue Net::HTTPError => e
      ServerProblem.new(error: e)
    rescue Errno::ECONNRESET => e
      ConnectionProblem.new(error: e)
    end

    protected

    attr_writer :url, :error

    def make_request(url:, redirect_limit: 5, redirect_count: 0)
      raise TooManyRedirectsError.new(url, redirect_count), 'Too many redirects' if redirect_limit == 0

      request = PhantomRequest.new(url)
      case request.response
      when Net::HTTPSuccess then request.response
      when Net::HTTPRedirection

        redirect_url = generate_redirect_url(
          previous_url: url,
          location: request.response['Location'],
        )

        make_request(
          url: redirect_url,
          redirect_limit: redirect_limit - 1,
          redirect_count: redirect_count + 1,
        )
      else
        request.response.error!
      end
    end

    def generate_redirect_url(previous_url:, location:)
      location_uri = URI(location)

      if location_uri.absolute?
        location_uri
      else
        previous_uri = URI(previous_url)

        URI.join("#{previous_uri.scheme}://#{previous_uri.host}", location_uri)
      end.to_s
    end
  end
end
