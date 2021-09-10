# frozen_string_literal: true

require 'faker'
require_relative 'oauth_service'

module Services
  class ApiV2Service

    attr_reader :oauth_service, :session

    def initialize(session:)
      @session = session || {}
      @oauth_service = Services::OauthService.new(session: @session)
      @base_url = "#{@session[:host]}/api/v2"
    end

    def handle_oauth_callback(params:)
      @oauth_service.process_callback(params: params)
    end

    def session
      @oauth_service.session.each { |key, val| @session[key.to_sym] = val }
      @session
    end

    # ApiClient Tests
    # ---------------
    def fetch_templates_for_client_test
      run_test_for_client(test_url: "#{@base_url}/templates")
    end

    def fetch_plans_for_client_test
      run_test_for_client(test_url: "#{@base_url}/plans")
    end

    def fetch_plan_for_client_test
      plans_json = run_test_for_client(test_url: "#{@base_url}/plans")
      plan_id = fetch_last_plan_id(json: plans_json)
      run_test_for_client(test_url: "#{@base_url}/plans/#{plan_id}")
    end

    def fetch_pdf_for_client_test
      plans_json = run_test_for_client(test_url: "#{@base_url}/plans")
      plan_id = fetch_last_plan_id(json: plans_json)
      run_test_for_client(test_url: "#{@base_url}/plans/#{plan_id}.pdf")
    end

    # User Tests
    # ----------
    def fetch_plans_for_user_test
      run_test_for_user(test_url: "#{@base_url}/plans")
    end

    def fetch_plan_for_user_test
      plans_json = run_test_for_user(test_url: "#{@base_url}/plans")
      plan_id = fetch_last_plan_id(json: plans_json)
      run_test_for_user(test_url: "#{@base_url}/plans/#{plan_id}")
    end

    def fetch_pdf_for_user_test
      plans_json = run_test_for_user(test_url: "#{@base_url}/plans")
      plan_id = fetch_last_plan_id(json: plans_json)
      run_test_for_user(test_url: "#{@base_url}/plans/#{plan_id}.pdf")
    end

    def add_doi_for_user_test
      plans_json = run_test_for_user(test_url: "#{@base_url}/plans")
      plan_id = fetch_last_plan_id(json: plans_json)
      doi = "doi:10.1234/#{Faker::Alphanumeric.alphanumeric(number: 10)}"
      doi_json = {
        dmp: {
          dmp_id: { type: "url", identifier: "#{@base_url}/plans/#{plan_id}" },
          dmproadmap_related_identifiers: [
            { descriptor: "is_referenced_by", type: "doi", identifier: doi }
          ]
        }
      }
      run_test_for_user(test_url: "#{@base_url}/related_identifiers", method: :post, payload: doi_json)
    end

    private

    def run_test_for_client(test_url:)
      @oauth_service.authorize_client
      p "  Requesting #{test_url} for the Client with token: #{@oauth_service.client_token.token}"
      process_response(test_url: test_url, response: @oauth_service.client_token.get(test_url))
    end

    def run_test_for_user(test_url:, method: :get, payload: {})
      @oauth_service.authorize_user
      p "  Requesting #{test_url} for the User with token: #{@oauth_service.auth_token.token}"
      response = @oauth_service.auth_token.get(test_url) if method == :get
      response = @oauth_service.auth_token.post(test_url, { body: payload.to_json }) if method == :post
      process_response(test_url: test_url, response: response)
    end

    def fetch_last_plan_id(json:)
      download_url = json['items'].last['dmp']&.fetch('dmproadmap_links', {})&.fetch('get', '') || 0
      download_url.split('/').last.gsub(%r{.[a-zA-Z]+$}, '')
    end

    def process_response(test_url:, response:)
      unless %w[200 201].include?(response&.status.to_s)
        session[:error] = "  Unexpected response from the API for #{test_url} - #{response&.code}."
      end

      JSON.parse(response.body)
    rescue JSON::ParserError => e
      p "  Unable to process JSON response from the API for #{test_url} status: #{response.status} error:  #{e.message}"
      p response.body
    end
  end

end
