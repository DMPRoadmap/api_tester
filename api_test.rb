require 'sinatra'
require 'httparty'
require 'oauth2'

enable :sessions

# Home page
# ----------
get '/' do
  session.clear
  @inputs = {}
  erb(:home)
end

# Test page
# ----------
post '/test_it' do
  if session[:host] == '' || session[:version] == ''
    @error = 'You must specify a Host and Version!'
    redirect back
  else
    # Just adding a dashed line to help with readability between tests
    p '---------------------------------------------------------------'
    process_params
    p 'Session:'
    pp session
    send(:"#{session[:version]}_test") unless session[:test_method].nil? || session[:test_path].nil?
    erb(:test_it)
  end
end

# Endpoint that the OAuth provider with send the Authorization code to
# ----------
get '/oauth2/callback' do
  process_params
  target_test = session[:test]
  oauth2_client

  p "  Authorization code (aka Access Grant) received from OAuth provider: #{params[:code]}"
  session[:code] = params['code']

  p "  Requesting access token for this test"
  @auth_token = @oauth_client.auth_code.get_token(params['code'], redirect_uri: @redirect_uri)
  p "  Token received from OAuth provider: #{@auth_token.token}"

  session[:test_path] = v2_find_a_test_plan if session[:test_path].include?('%{id}')
  p "  Requesting data from #{session[:test_path]}"
  resp = @auth_token.send(session[:test_method].to_sym, "#{session[:host]}/api/#{session[:version]}/#{session[:test_path]}", body: @payload)

  unless %w[200 201].include?(resp&.status.to_s)
    @error = "  Unexpected response from the API - #{resp&.status}. See UI for details."
  end

  p "  Successful response received from OAuth2 provider ... see UI for details"
  @data = (session[:test_path] =~ /\.pdf$/).nil? ? JSON.parse(resp&.body) : resp.body.to_s
  erb(:test_it)
rescue JSON::ParserError => e
  @error = "Unable to parse the response to the oauth2/callback - #{e.message}"
rescue StandardError => e
  @error = "Unable to run this oauth2 test - #{e.message}"
end

private

# Store info in the session
# ----------
def process_params
  # Fetch and store the user entered form data
  session[:host] = params['host_name'] || session[:host]
  session[:version] = params['api_version'] || session[:version]
  session[:api_token] = params['api_token'] || session[:api_token]
  session[:client_id] = params['client_id'] || session[:client_id]
  session[:client_secret] = params['client_secret'] || session[:client_secret]
  # Figure out our general auth method based on the API version
  @require_api_token = %w[v0].include?(session[:version])
  @require_credentials = %w[v1 v2].include?(session[:version])
  # Convert the value of the button into a HTTP method, path and whether or not this is OAuth
  identify_test
  @redirect_uri = 'http://localhost:4567/oauth2/callback'
  # User entered content that should be sent through to the API test as :body
  @payload = params['test_body'] || session[:payload]
end

# Version Tests
# -------------------------------------------------------------------------

# Version 0
# ----------
def v0_test
  if session[:api_token].nil? || session[:api_token] == ''
    @error = 'You MUST provide an API token!'
  else
    @headers = default_headers.merge({ 'Authorization': "Token token=#{session[:api_token]}" }).compact
    p "  Requesting data from the v0 API"
    resp = HTTParty.send(session[:test_method].to_sym,
                          "#{session[:host]}/api/v0/#{session[:test_path]}",
                          body: @payload,
                          headers: @headers,
                          follow_redirects: true,
                          debug: true)

    unless %w[200 201].include?(resp&.code.to_s)
      @error = "  Unexpected response from the v0 API - #{resp&.code}. See UI for details."
    end
    p "  Successful response received from v0 API ... see UI for details"
    @data = JSON.parse(resp&.body)
  end
rescue JSON::ParserError => e
  @error = "Unable to process response from the v0 API - #{e.message}"
end

# Version 1
# ----------
def v1_test
  if session[:client_id].nil? || session[:client_secret].nil?
    @error = 'You MUST provide a Client ID (or email) and Client Secret (or API token)!'
  else
    # If we've already authenticated just reuse the auth token in the session
    @auth_token = session[:auth_token].nil? ? v1_auth : session[:auth_token]
    session[:auth_token] = @auth_token

    unless @auth_token.nil?
      @headers = default_headers.merge(token_for_header).compact
      p "  Requesting data from the v1 API"
      resp = HTTParty.send(session[:test_method].to_sym,
                           "#{session[:host]}/api/v1/#{session[:test_path]}",
                           body: @payload,
                           headers: @headers,
                           follow_redirects: true,
                           debug: true)

      unless %w[200 201].include?(resp&.code.to_s)
        @error = "  Unexpected response from the v1 API - #{resp&.code}. See UI for details."
      end
      p "  Successful response received from v1 API ... see UI for details"
      @data = JSON.parse(resp&.body)
    end
  end
rescue JSON::ParserError => e
  @error = "Unable to parse the response from the v1 API - #{e.message}"
rescue StandardError => e
  @error = "Unable to run this v1 test - #{e.message}"
end

# Version 2
# ----------
def v2_test
  if session[:client_id].nil? || session[:client_secret].nil?
    @error = 'You MUST provide a Client ID (or email) and Client Secret (or API token)!'
  else
    oauth2_client
    v2_auth

    if session[:as_oauth].nil?
      # The client is accessing data that does not require User authorization
      @payload = {} if @payload.nil?
      p "  Requesting data via the Access Token for this ApiClient from v2 API: #{@client_token.token}"
      resp = @client_token.send(session[:test_method].to_sym, "#{session[:host]}/api/v2/#{session[:test_path]}", body: @payload.to_json)
    else
      # The client is trying to access data that the User must authorize
      if !@auth_token.nil? && @auth_token != ""
        # If we've already received an authorization token just reuse it
        p "  Reusing Access Token for the User for the v2 API: #{@auth_token.token}"
        resp = @auth_token.send(session[:test_method].to_sym, "#{session[:host]}/api/#{session[:version]}/#{session[:test_path]}", body: @payload)
      else
        p "  Requesting an Access Token for the User from the v2 API."
        redirect @oauth_client.auth_code.authorize_url(redirect_uri: @redirect_uri, scope: 'read_dmps')
      end
      # User will be redirected to /oauth2/callback above
    end

    unless %w[200 201].include?(resp&.status.to_s)
      @error = "  Unexpected response from the v2 API - #{resp&.status}. See below for details."
    end
    p "  Successful response received from v2 API ... see UI for details"
    @data = JSON.parse(resp&.body)
  end
rescue OAuth2::Error => e
  @error = "Unable to authenticate for the v2 API - #{e.message}"
end

# API Request Helpers
# -------------------------------------------------------------------------

def default_headers
  { 'Content-Type': 'application/json', 'Accept': 'application/json' }
end

def client_credentials
  { grant_type: 'client_credentials', client_id: session[:client_id], client_secret: session[:client_secret] }
end

def api_token_credentials
  { grant_type: 'authorization_code', email: session[:client_id], code: session[:client_secret] }
end

def token_for_header
  return {} if @auth_token.nil? || @auth_token == ''

  { 'Authorization': "Bearer #{@auth_token}" }
end

# Convert the value of the clicked button into an HTTP method, path and whether or not this is OAuth
# ----------
def identify_test
  non_test_button_params = %w[host_name api_token client_id client_secret auth_token]

  # Find the test button submitted
  test_buttons = params.reject { |k, _v| non_test_button_params.include?(k) }.keys
  clicked_button = test_buttons.select { |name| name =~ /^[a-zA-Z]+\+/ }.last || ''
  return if clicked_button.nil? ||  clicked_button == ''

  # Extract the HTTP method and URL path from the name (e.g. "get+templates")
  session[:test_method], session[:test_path], session[:as_oauth] = clicked_button.split('+')
end

# Initialize and authorize the OAuth2 client
# ----------
def oauth2_client
  @oauth_client = OAuth2::Client.new(session[:client_id], session[:client_secret], { site: session[:host] })
  @oauth_client.auth_code.authorize_url(redirect_uri: @redirect_uri)
end

# Version Specific Helpers
# -------------------------------------------------------------------------

# Authenticate against the v1 API
# ----------
def v1_auth
  # Switch the type of credentials used based on whether the client_id is an email address
  creds = (session[:client_id] =~ URI::MailTo::EMAIL_REGEXP) == 0 ? api_token_credentials : client_credentials

  p "  Requesting access token from v1 API using the specified credentials"
  resp = HTTParty.post("#{session[:host]}/api/v1/authenticate",
                        body: creds.to_json,
                        headers: @headers,
                        follow_redirects: true,
                        debug: true)

  unless resp&.code == 200
    @error = "  Unexpected response from the v1 API auth method - #{resp&.code}. See UI for details."
  end
  p "  v1 authentication success"
  token = JSON.parse(resp&.body)['access_token']
rescue JSON::ParserError => e
  @error = "  Unable to parse the access token response from the v1 API - #{e.message}"
  nil
rescue StandardError => e
  @error = "  Unable to authenticate via the v1 API - #{e.message}"
  nil
end

# Authenticate against the v2 API
# ----------
def v2_auth
  # Fetch the access token
  if session[:access_token].nil? || session[:access_token] == ""
    # If we don't yet have an access token then we need to auth the ApiClient
    if session[:client_token].nil?
      p "  Requesting access token from the v2 API for this ApiClient"
      @client_token = @oauth_client.client_credentials.get_token
    else
      p "  Reusing access token from the v2 API for this ApiClient"
      @client_token = OAuth2::AccessToken.from_hash(@oauth_client, session[:client_token])
    end
    session[:client_token] = @client_token.to_hash
  else
    # We already have an access token for the User
    p "  Reusing access token for the User"
    @auth_token = OAuth2::AccessToken.from_hash(@oauth_client, session[:access_token])
    session[:access_token] = @auth_token.to_hash
  end
end

# If the test is for a specific plan then we need to first call the index path
# to find a Plan to test against
# ----------
def v2_find_a_test_plan
  path_parts = session[:test_path].split('/')
  path = path_parts.compact.reject { |part| part.include?('%{id}') }.join

  p "  Fetching list of available Plans from API v2"
  resp = @auth_token.send(session[:test_method].to_sym, "#{session[:host]}/api/v2/#{path}", body: @payload.to_json)

  unless %w[200 201].include?(resp&.status.to_s)
    @error = "  Unexpected response when trying to find a test Plan for API v2 - #{resp&.status}. See UI for details."
    @data = JSON.parse(resp&.body)
  end

  p "  Found a Plan to use for testing"
  plans = JSON.parse(resp&.body)
  id = plans['items'].last['dmp']&.fetch('dmproadmap_links', {})&.fetch('download', '') || 0
  session[:test_path] % { id: id.split('/').last.gsub(%r{.[a-zA-Z]+$}, '') }
rescue JSON::ParserError => e
  @error = "  Unable to locate a Plan from API v2 to test with!"
  @data = nil
end