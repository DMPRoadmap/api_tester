require 'httparty'

HOST = ARGV[0]
NAME = ARGV[1]
CLIENT_ID = ARGV[2]
CLIENT_SECRET = ARGV[3]
DEFAULT_HEADERS = {
  'Content-Type': 'application/json',
  'Accept': 'application/json',
  'Server-Agent': "#{NAME} (#{CLIENT_ID})"
}

def retrieve_auth_token
  payload = {
    grant_type: 'client_credentials',
    client_id: CLIENT_ID,
    client_secret: CLIENT_SECRET
  }
  target = "#{HOST}/api/v1/authenticate"

  p "Authentication attempt:"
  p "    Target: #{target}"
  p "    Data: #{payload}"
  p "    Headers: #{DEFAULT_HEADERS}"
  p "-----------------------"
  p

  resp = HTTParty.post(target, body: payload.to_json, headers: DEFAULT_HEADERS, debug: true)
  response = JSON.parse(resp.body)

  p "Unable to authenticate: #{resp.code} - #{response.inspect}" unless resp.code == 200
  return nil unless resp.code == 200

  token = response
  {
    'Authorization': "#{token['token_type']} #{token['access_token']}"
  }
end

def retrieve_templates(token:, page: 1)
  target = "#{HOST}/api/v1/templates?page=#{page}"
  headers = DEFAULT_HEADERS.merge(token)

  p "Template listing attempt:"
  p "    Target: #{target}"
  p "    Headers: #{headers}"
  p "-----------------------"
  p

  resp = HTTParty.get(target, headers: headers, debug: true)
  p "Unable to get templates: #{resp.code} - #{resp.body}" unless resp.code == 200
  resp.code == 200 ? JSON.parse(resp.body) : nil
end

def retrieve_plans(token:, page: 1)
  target = "#{HOST}/api/v1/plans?page=#{page}"
  headers = DEFAULT_HEADERS.merge(token)

  p "Plan/DMP listing attempt:"
  p "    Target: #{target}"
  p "    Headers: #{headers}"
  p "-----------------------"
  p

  resp = HTTParty.get(target, headers: headers, debug: true)
  p "Unable to get plans: #{resp.code} - #{resp.body}" unless resp.code == 200
  resp.code == 200 ? JSON.parse(resp.body) : nil
end

if ARGV.any? && ARGV.length == 4
  # Authenticate
  token = retrieve_auth_token
  if token.is_a?(Hash)
    p "TOKEN:"
    pp token.inspect
    p ''

    # Retrieve the public templates
    pp retrieve_templates(token: token).inspect
    p ''

    # Retrieve page 2 of the public templates
    pp retrieve_plans(token: token).inspect

    # You can then add further tasks
  end
else
  p "Missing essential information. This script requires 3 arguments. The host (e.g. https://my.org.edu), your client name, client_id and the client_secret."
  p "Please retry with `ruby dmproadmap_api_tester.rb http://localhost:3000 dmptool 12345 abcdefg`"
end
