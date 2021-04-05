require 'sinatra'
require 'httparty'
require 'oauth2'
require 'nokogiri' # For processing the results of the DMPRoadmap PDF

enable :sessions

get '/' do
  @inputs = {}
  erb(:home)
end

post '/test_it' do
  if @host == '' || @version == ''
    @error = 'You must specify a Host and Version!'
    redirect back
  else
    process_params
    send(:"#{@version}_test") unless @test_method.nil? || @test_path.nil?
    erb(:test_it)
  end
end

get '/oauth2/callback' do
  process_params

  target_test = session[:test]

  session[:code] = params['code'] unless params['code'].nil?
  oauth2_client

  @auth_token = @oauth_client.auth_code.get_token(@code, redirect_uri: @redirect_uri)
  @test_path = v2_find_a_test_plan if @test_path.include?('%{id}')

  resp = @auth_token.send(@test_method.to_sym, "#{@host}/api/#{@version}/#{@test_path}", body: @payload)

  unless %w[200 201].include?(resp&.status.to_s)
    @error = "Unexpected response from the API - #{resp&.status}. See below for details."
  end

  @data = (@test_path =~ /\.pdf$/).nil? ? JSON.parse(resp&.body) : resp.body.to_s
  erb(:test_it)
rescue JSON::ParserError => e
  @error = "Unable to parse the response to the oauth2/callback - #{e.message}"
rescue StandardError => e
  @error = "Unable to run this oauth2 test - #{e.message}"
end

private

def process_params
  @host = params['host_name'] || session[:host_name]
  @version = params['api_version'] || session[:api_version]

  @require_api_token = %w[v0].include?(@version)
  @require_credentials = %w[v1 v2].include?(@version)

  @api_token = params['api_token'] || session[:api_token]
  @client_id = params['client_id'] || session[:client_id]
  @client_secret = params['client_secret'] || session[:client_secret]

  identify_test
  @test_method = session[:test_method] if @test_method.nil?
  @test_path = session[:test_path] if @test_path.nil?

  @auth_token = params['auth_token']
  @code = params['code']

  @redirect_uri = 'http://localhost:4567/oauth2/callback'

  # User entered content that should be sent through to the API test as :body
  @payload = params['test_body'] || session[:payload]
end

def params_to_session
  session[:host_name] = @host
  session[:api_version] = @version

  session[:api_token] = @api_token
  session[:client_id] = @client_id
  session[:client_secret] = @client_secret

  session[:test_method] = @test_method
  session[:test_path] = @test_path
  session[:payload] = @payload
end

# Version Tests
# -------------------------------------------------------------------------

def v0_test
  if @api_token.nil?
    @error = 'You MUST provide an API token!'
  else
    @headers = default_headers.merge({ 'Authorization': "Token token=#{@api_token}" }).compact
      resp = HTTParty.send(@test_method.to_sym,
                           "#{@host}/api/v0/#{@test_path}",
                           body: @payload,
                           headers: @headers,
                           follow_redirects: true,
                           debug: true)

      unless %w[200 201].include?(resp&.code.to_s)
        @error = "Unexpected response from the API - #{resp&.code}. See below for details."
      end
      @data = JSON.parse(resp&.body)
  end
rescue JSON::ParserError => e
  @error = "Unable to process response - #{e.message}"
end

def v1_test
  if @client_id.nil? || @client_secret.nil?
    @error = 'You MUST provide a Client ID (or email) and Client Secret (or API token)!'
  else
    @auth_token = v1_auth

    unless @auth_token.nil?
      @headers = default_headers.merge(token_for_header).compact
      resp = HTTParty.send(@test_method.to_sym,
                           "#{@host}/api/v1/#{@test_path}",
                           body: @payload,
                           headers: @headers,
                           follow_redirects: true,
                           debug: true)

      unless %w[200 201].include?(resp&.code.to_s)
        @error = "Unexpected response from the API - #{resp&.code}. See below for details."
      end
      @data = JSON.parse(resp&.body)
    end
  end
rescue JSON::ParserError => e
  @error = "Unable to parse the response from the API - #{e.message}"
rescue StandardError => e
  @error = "Unable to run this test - #{e.message}"
end

def v2_test
  if @client_id.nil? || @client_secret.nil?
    @error = 'You MUST provide a Client ID (or email) and Client Secret (or API token)!'
  else
    oauth2_client

    if @as_oauth.nil?
      @auth_token = @oauth_client.client_credentials.get_token

      @payload = {} if @payload.nil?

      resp = @auth_token.send(@test_method.to_sym, "#{@host}/api/v2/#{@test_path}", body: @payload.to_json)
    else
      params_to_session
      redirect @oauth_client.auth_code.authorize_url(redirect_uri: @redirect_uri, scope: 'read_dmps')
      # User will be redirected to /oauth2/callback above
    end

    unless %w[200 201].include?(resp&.status.to_s)
      @error = "Unexpected response from the API - #{resp&.status}. See below for details."
    end
    @data = JSON.parse(resp&.body)
  end
rescue OAuth2::Error => e
  @error = "Unable to authenticate - #{e.message}"
end

# API Request Helpers
# -------------------------------------------------------------------------

def default_headers
  { 'Content-Type': 'application/json', 'Accept': 'application/json' }
end

def client_credentials
  { grant_type: 'client_credentials', client_id: @client_id, client_secret: @client_secret }
end

def api_token_credentials
  { grant_type: 'authorization_code', email: @client_id, code: @client_secret }
end

def token_for_header
  return {} if @auth_token.nil? || @auth_token == ''

  { 'Authorization': "Bearer #{@auth_token}" }
end

def identify_test
  non_test_button_params = %w[host_name api_token client_id client_secret auth_token]

  # Find the test button submitted
  test_buttons = params.reject { |k, _v| non_test_button_params.include?(k) }.keys
  clicked_button = test_buttons.select { |name| name =~ /^[a-zA-Z]+\+/ }.last || ''

  # Extract the HTTP method and URL path from the name (e.g. "get+templates")
  @test_method, @test_path, @as_oauth = clicked_button.split('+')
end

def oauth2_client
  @oauth_client = OAuth2::Client.new(@client_id, @client_secret, { site: @host })
  @oauth_client.auth_code.authorize_url(redirect_uri: @redirect_uri)
end

# Version Specific Helpers
# -------------------------------------------------------------------------

def v1_auth
  # Switch the type of credentials used based on whether the client_id is an email address
  creds = (@client_id =~ URI::MailTo::EMAIL_REGEXP) == 0 ? api_token_credentials : client_credentials

  resp = HTTParty.post("#{@host}/api/v1/authenticate",
                        body: creds.to_json,
                        headers: @headers,
                        follow_redirects: true,
                        debug: true)

  @error = "Unexpected response form host - #{resp&.code}. See below for details." unless resp&.code == 200
  JSON.parse(resp&.body)['access_token']
rescue JSON::ParserError => e
  @error = "Unable to parse the api/v1/authenticate response - #{e.message}"
  nil
rescue StandardError => e
  @error = "Unable to authenticate via api/v1/authenticate - #{e.message}"
  nil
end

# If the test is for a specific plan then we need to first call the index path and grab the last record
def v2_find_a_test_plan
  path_parts = @test_path.split('/')
  path = path_parts.compact.reject { |part| part.include?('%{id}') }.join

  resp = @auth_token.send(@test_method.to_sym, "#{@host}/api/v2/#{path}", body: @payload.to_json)

  unless %w[200 201].include?(resp&.status.to_s)
    @error = "Unexpected response when trying to locate a test Plan - #{resp&.status}. See below for details."
    @data = JSON.parse(resp&.body)
  end

  plans = JSON.parse(resp&.body)
  id = plans['items'].last['dmp']&.fetch('dmproadmap_links', {})&.fetch('download', '') || 0
  @test_path % { id: id.split('/').last.gsub(%r{.[a-zA-Z]+$}, '') }
rescue JSON::ParserError => e
  @error = "Unable to locate a Plan to test with!"
  @data = nil
end