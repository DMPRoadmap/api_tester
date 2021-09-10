# frozen_string_literal: true

require 'oauth2'

module Services

  # Place to store the Authorization redirect URL and bubble back up to api_test.rb
  class OauthRedirect < StandardError

  end

  class OauthService

    attr_reader :oauth_client, :client_token, :auth_token, :user_token, :direct_user_token,
                :redirect_uri, :session

    def initialize(session:)
      @session = session || {}
      @redirect_uri = 'http://localhost:4567/oauth2/callback'

      @oauth_client = OAuth2::Client.new(
        @session[:client_id], @session[:client_secret], { site: @session[:host] }
      )
    end

    # Process an OAuth callback from a request for User authorization
    def process_callback(params:)
      p "  Authorization code received: #{params[:code]}"
      @session[:code] = params['code']
      authorize_user

      p "  Running test #{@session[:callback_test]}"
      @session[:callback_test]
    end

    def token_exists?(token_name:)
      !@session[token_name.to_sym].nil? && @session[token_name.to_sym] != ''
    end

    # Fetch an authorization token for the ApiClient
    def authorize_client
      if token_exists?(token_name: :client_token)
        p "  Reusing access token from the v2 API for the ApiClient"
        @client_token = OAuth2::AccessToken.from_hash(@oauth_client, @session[:client_token])
      else
        p "  Requesting access token from the v2 API for the ApiClient"
        @client_token = @oauth_client.client_credentials.get_token({ scope: 'public read_dmps edit_dmps' })
      end
      @session[:client_token] = @client_token.to_hash
    rescue OAuth2::Error => e
      p "  OAuth error - #{e.message}"
    end

    # Fetch an authorization token for the User on behalf of the ApiClient
    def authorize_user
      if token_exists?(token_name: :auth_token)
        p "  Reusing access token from the v2 API for the User"
        @auth_token = OAuth2::AccessToken.from_hash(@oauth_client, @session[:auth_token])
      elsif @session[:code].nil? || @session[:code] == ''
        # Stash the original test for use during the callback phase
        @session[:callback_test] = @session[:test]
        # We don't have an authorization code yet so reirect to the provider for signin/authorization
        p "  No authorization code available so redirecting User for OAuth approval"
        raise OauthRedirect.new(@oauth_client.auth_code.authorize_url(redirect_uri: @redirect_uri,
                                                                      scope: 'public read_dmps edit_dmps'))
      else
        p "  Requesting access token from the v2 API for this User's authorization code"
        @auth_token = @oauth_client.auth_code.get_token(@session[:code], redirect_uri: @redirect_uri)
      end
      @session[:auth_token] = @auth_token.to_hash
    rescue OAuth2::Error => e
      if e.message.starts_with?('invalid_grant:')
        # Authorization code has expired
        p "  Authorization code is expired fetching a new code"
        raise OauthRedirect.new(@oauth_client.auth_code.authorize_url(redirect_uri: @redirect_uri,
                                                                      scope: 'public read_dmps edit_dmps'))
      else
        p "  OAuth error during authorization code fetch - #{e.message}"
      end
    end

  end
end
