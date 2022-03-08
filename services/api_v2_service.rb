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

    def create_plan_for_client_test
      now = Time.now
      json = {
        dmp: {
          title: "Testing V2 API plan creation #{Time.now}",
          description: "<p>#{Faker::Lorem.paragraph}</p>",
          language: "eng",
          ethical_issues_exist: %w[yes no unknown].sample,
          dmp_id: {
            type: "other", identifier: "foo-#{Faker::Number.number}"
          },
          contact: {
            name: Faker::Movies::StarWars.character,
            mbox: Faker::Internet.email,
            affiliation: { name: "University of California, Office of the President" }
          },
          contributor: [{
            name: Faker::Movies::StarWars.character,
            mbox: Faker::Internet.email,
            role: ["http://credit.niso.org/contributor-roles//investigation"],
            affiliation: {
              name: "University of California, Office of the President (UCOP)",
              affiliation_id: {
                type: "ror", identifier: "https://ror.org/00pjdza24"
              }
            }
          }],
          project: [{
            title: "Testing V2 API",
            description: "<p>#{Faker::Lorem.paragraph}</p>",
            start: "#{now.year}-#{now.month}-#{now.day}T00:00:00Z",
            end: "2024-02-19T00:00:00Z",
            funding: [{
              name: "National Institutes of Health (NIH)",
              funder_id: {
                type: "ror",
                identifier: "https://ror.org/01cwqze88"
              },
              funding_status: "planned",
              dmproadmap_funding_opportunity_id: {
                type: "other", identifier: Faker::Number.number
              }
            }]
          }],
          dmproadmap_template: { id: 1224196207 }
        }
      }
      run_test_for_client(test_url: "#{@base_url}/plans", method: :post, payload: json)
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
            { descriptor: "documents", type: "doi", identifier: doi, work_type: "dataset" }
          ]
        }
      }
      run_test_for_user(test_url: "#{@base_url}/related_identifiers", method: :post, payload: doi_json)
    end

    private

    def run_test_for_client(test_url:, method: :get, payload: {})
      @oauth_service.authorize_client
      p "  Requesting #{test_url} for the Client with token: #{@oauth_service.client_token.token}"
      response = @oauth_service.client_token.get(test_url) if method == :get
      response = @oauth_service.client_token.post(test_url, { body: payload.to_json }) if method == :post
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
