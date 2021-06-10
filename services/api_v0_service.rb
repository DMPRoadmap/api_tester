# frozen_string_literal: true

require 'faker'
require 'httparty'

module Services
  class ApiV0Service

    attr_reader :session

    def initialize(session:)
      @session = session || {}
      @base_url = "#{@session[:host]}/api/v0"
    end

    # Standard API Token tests
    # ---------------
    def fetch_templates_test
      run_test_for_token(test_url: "#{@base_url}/templates", method: :get)
    end

    def fetch_plans_test
      run_test_for_token(test_url: "#{@base_url}/plans", method: :get)
    end

    private

    def default_headers
      {
        'Accept': 'application/json',
        'Content-Type': 'application/json'
      }
    end

    def run_test_for_token(test_url:, method: :get)
      if session[:api_token].nil? || session[:api_token] == ''
        @error = 'You MUST provide an API token!'
      else
        @headers = default_headers.merge({ 'Authorization': "Token token=#{session[:api_token]}" }).compact
        p "  Requesting data from the v0 API"
        resp = HTTParty.send(method, test_url, body: @payload, headers: @headers, follow_redirects: true,
                                               debug: true)

        unless %w[200 201].include?(resp&.code.to_s)
          @error = "  Unexpected response from the v0 API - #{resp&.code}. See UI for details."
        end
        p "  Successful response received from v0 API ... see UI for details"
        @data = JSON.parse(resp&.body)
      end
    rescue JSON::ParserError => e
      @error = "Unable to process response from the v0 API - #{e.message}"
      p resp&.body
    end

  end
end
