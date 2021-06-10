# frozen_string_literal: true

require 'faker'
require 'httparty'

module Services
  class ApiV1Service

    attr_reader :session, :token

    def initialize(session:)
      @session = session || {}
      @base_url = "#{@session[:host]}/api/v1"
    end

    # Standard API client id+secret
    def fetch_templates_test
      @token = authenticate

pp @token

      run_test_for_client(test_url: "#{@base_url}/templates", method: :get)
    end

    def fetch_plans_test
      @token = authenticate
      run_test_for_client(test_url: "#{@base_url}/plans", method: :get)
    end

    private

    def default_headers
      {
        'Accept': 'application/json',
        'Content-Type': 'application/json'
      }
    end

    def run_test_for_client(test_url:, method: :get)
      if session[:client_id].nil? || session[:client_id] == '' ||
         session[:client_secret].nil? || session[:client_secret] == ''
        @error = 'You MUST provide an API client_id and client_secret!'
      else
        @headers = default_headers.merge({ 'Authorization': @token }).compact

p @headers

        p "  Requesting data from the v1 API"
        resp = HTTParty.send(method, test_url, body: @payload, headers: @headers, follow_redirects: true,
                                               debug: true)

        unless %w[200 201].include?(resp&.code.to_s)
          @error = "  Unexpected response from the v1 API - #{resp&.code}. See UI for details."
        end
        p "  Successful response received from v1 API ... see UI for details"
        @data = JSON.parse(resp&.body)
      end
    rescue JSON::ParserError => e
      @error = "Unable to process response from the v1 API - #{e.message}"
      p resp&.body
    end

    def authenticate
      return @token unless @token.nil? || @token == ''

      @payload = {
        grant_type: "client_credentials",
        client_id: @session[:client_id],
        client_secret: @session[:client_secret]
      }.to_json

      p "  Authenticating and requesting token from v1 API"
      resp = HTTParty.post("#{@base_url}/authenticate", body: @payload, headers: default_headers,
                                                        follow_redirects: true, debug: true)

      unless %w[200].include?(resp&.code.to_s)
        @error = "  Unable to authenticate for v1 API - #{resp&.code}. See UI for details."
      end
      p "  Token received from v1 API ... see UI for details"
      data = JSON.parse(resp&.body)

      "#{data["token_type"]} #{data["access_token"]}"
    rescue JSON::ParserError => e
      @error = "Unable to process response from the v1 API - #{e.message}"
      p resp&.body
      nil
    end

  end
end
