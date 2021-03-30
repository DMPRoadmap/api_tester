require 'sinatra'
require 'httparty'

get '/' do
  erb :index
end

post '/test' do
  @inputs = params_to_hash

  p "Parameters:"
  pp @inputs

  unless @inputs[:host_name] == '' ||
         @inputs[:client_id] == '' ||
         @inputs[:client_secret] == '' ||
         @inputs[:test] == ''

    target = "#{@inputs[:host_name]}/#{@inputs[:test]}"
    @inputs[:test] == 'oauth/authorize' ? call_oauth_api(target: target) : call_api(target: target)
  else
    @error = "You must specify the Host and Client credentials along with a specific test!"
  end

  erb(:index)
end

private

def call_api(target:)
  return nil if target == "#{@inputs[:host_name]}/"

  @payload = @inputs[:test_type] == 'authorization_code' ? authorization_code : client_credentials
  @headers = default_headers.merge(token_for_header).compact

  resp = HTTParty.send(@inputs[:test_method], target, body: @payload.to_json, headers: @headers,
                       debug: true, follow_redirects: true)

  @error = "Unexpected response form host - #{resp&.code}. See below for details." unless resp&.code == 200
  @data = JSON.parse(resp&.body)
  @token = @data['access_token'] || @inputs[:token]
rescue JSON::ParserError => e
  @error = "JSON Parse error in response body - #{e.message}"
  nil
end

# Call the Oauth Authorization enpoint
def call_oauth_api(target:)
  return nil if target == "#{@inputs[:host_name]}/"

  @payload = @inputs[:test_type] == 'authorization_code' ? authorization_code : client_credentials
  @payload = @payload.merge({
    redirect_uri: CGI.escape('http://localhost:4567/users/auth/callback'),
    response_type: 'code',
    scope: 'read',
    state: @inputs[:token],
    format: 'HTML'
  })
  @headers = { 'Accept': 'text/html,application/xhtml+xml,application/xml' }

  target = "#{target}?#{@payload.map { |k, v| "#{k}=#{v}" }.join('&')}"

p "TARGET: #{target}"
p "HEADERS:"
pp headers

  resp = HTTParty.get(target, headers: @headers, debug: true, follow_redirects: true)

  @error = "Unexpected response form host - #{resp&.code}. See below for details." unless resp&.code == 200
  @data = JSON.parse(resp&.body)
  @token = @data['access_token'] || @inputs[:token]
rescue JSON::ParserError => e
  @error = "JSON Parse error in response body - #{e.message}"
  nil
end

# Helper methods
# -----------------------------------

def params_to_hash
  hash = {
    host_name: params['host_name'],
    client_id: params['client_id'],
    client_secret: params['client_secret'],

    token: params["token"],
    code: params["code"]
  }
  test_name_parts = test_from_params.split('+')
  hash[:test_method] = test_name_parts[0]
  hash[:test] = test_name_parts[1].gsub('_', '/')
  hash
end

def test_from_params
  buttons = params.reject { |k, _v| %w[host_name client_id client_secret token code].include?(k) }.keys
  buttons.select { |name| name =~ /^[a-zA-Z]+\+/ }.last
end

def default_headers
  { 'Content-Type': 'application/json', 'Accept': 'application/json' }
end

def token_for_header
  return {} if @inputs[:token].nil? || @inputs[:token] == ''

  { 'Authorization': "Bearer #{@inputs[:token]}" }
end

def client_credentials
  { grant_type: 'client_credentials', client_id: @inputs[:client_id], client_secret: @inputs[:client_secret] }
end

def authorization_code
  { grant_type: 'authorization_code', client_id: @inputs[:client_id], code: @inputs[:code] }
end