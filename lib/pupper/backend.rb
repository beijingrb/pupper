require 'pupper/parse_json'

module Pupper
  # Provides an interface to build an API Client, that can be used by [Model]
  class Backend
    class BaseUrlNotDefined < StandardError; end

    attr_reader :client, :model

    delegate :base_url, :headers, to: :class

    class << self
      # Sets the base URL the API client will call
      # @return [String] the URL (plus - optionally - a path)
      attr_writer :base_url, :headers

      def headers
        @headers ||= {}
      end

      def base_url
        if @base_url.nil?
          raise BaseUrlNotDefined, <<-ERR
            Add the following to #{name} to make it work:

              self.base_url = "https://example.com/some/path"

            Making sure to change the URL to something useful :)))
          ERR
        end

        @base_url
      end
    end

    %i(get put post delete patch).each do |name|
      class_eval <<-RB.strip_heredoc, __FILE__, __LINE__
        def #{name}(*args)
          client.send(:#{name}, *args).body
        end
      RB
    end

    def initialize
      @client = Faraday.new(base_url, ssl: Pupper.config.ssl) do |builder|
        builder.request :json
        builder.use Pupper::ParseJson
        builder.response :logger if Pupper.config.logging?
        builder.response :raise_error
        builder.adapter :typhoeus
        builder.headers = headers.merge!('User-Agent' => Pupper.config.user_agent)
      end
    end

    def register_model(model)
      @model = model
    end
  end
end
