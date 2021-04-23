require 'sinatra'
require 'httparty'

require_relative 'services/api_v2_service'
require_relative 'services/oauth_service'

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

    api_service = Services::ApiV0Service.new(session: session) if session[:version] == 'v0'
    api_service = Services::ApiV1Service.new(session: session) if session[:version] == 'v1'
    api_service = Services::ApiV2Service.new(session: session) if session[:version] == 'v2'

    @require_api_token = session[:version] == 'v0'
    @require_credentials = %w[v1 v2].include?(session[:version])

    @data = session[:test].nil? || session[:test] == '' ? nil : api_service.send(:"#{session[:test]}")
    update_session(hash: api_service.session)
    erb(:test_it)

  end
rescue Services::OauthRedirect => e
  update_session(hash: api_service.session)
  redirect e
end

# Endpoint that the OAuth provider with send the Authorization code to
# ----------
get '/oauth2/callback' do
  process_params
  p 'Session:'
  pp session

  api_service = Services::ApiV2Service.new(session: session) if session[:version] == 'v2'
  @require_credentials = true

  api_service.handle_oauth_callback(params: params)
  @data = api_service.send(:"#{session[:callback_test]}")

  update_session(hash: api_service.session)
  session[:test] = session[:callback_test]
  session.delete(:callback_test)

  erb(:test_it)
end

private

def which_test?(args: [])
  non_test_button_params = %w[host_name api_version api_token client_id client_secret]

  # Find the test button that was submitted
  test = args.reject { |k, _v| non_test_button_params.include?(k) }.keys&.last
  (test.nil? || test == '') ? nil : "#{test}_test"
end

def update_session(hash:)
  hash.each { |key, val| session[key.to_sym] = val }
end

# Store info in the session
# ----------
def process_params
  # Fetch and store the user entered form data
  session[:host] = params['host_name'] || session[:host]
  session[:version] = params['api_version'] || session[:version]

  session[:api_token] = params['api_token'] || session[:api_token]
  session[:client_id] = params['client_id'] || session[:client_id]
  session[:client_secret] = params['client_secret'] || session[:client_secret]

  session[:test] = which_test?(args: params)
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

# Version Specific Helpers
# -------------------------------------------------------------------------

# V1 Custom JWT
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
