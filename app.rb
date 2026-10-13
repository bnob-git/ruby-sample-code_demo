# frozen_string_literal: true

require "bundler/setup"
require "dotenv/load"
require "json"
require "securerandom"
require "sinatra/base"
require "oauth2"

# Sample ID.me OAuth 2.0 (authorization code) client.
# Get your credentials by registering your app at https://developer.id.me
# Set IDME_BASE_URL=http://localhost:4568 to use the local mock (see mock_idme.rb).
class IdmeSampleApp < Sinatra::Base
  REAL_IDME_BASE_URL = "https://api.id.me"
  MIN_SESSION_SECRET_BYTES = 64

  base_url = ENV.fetch("IDME_BASE_URL", REAL_IDME_BASE_URL)
  use_mock = base_url != REAL_IDME_BASE_URL

  set :app_file, __FILE__
  set :client_id, ENV.fetch("IDME_CLIENT_ID", "YOUR_CLIENT_ID")
  set :client_secret, ENV.fetch("IDME_CLIENT_SECRET", "YOUR_CLIENT_SECRET")
  set :redirect_uri, ENV.fetch("IDME_REDIRECT_URI", "http://localhost:4567/callback")
  set :attributes_url, "#{base_url}/api/public/v3/attributes.json"
  set :use_mock, use_mock
  # Possible scope values: "military", "student", "responder", "teacher"
  set :scope, ENV.fetch("IDME_SCOPE", use_mock ? "military" : "YOUR_SCOPE_VALUE")

  session_secret = ENV.fetch("SESSION_SECRET", "")
  if session_secret.empty?
    raise KeyError, "SESSION_SECRET must be set in production" if production?

    session_secret = SecureRandom.hex(MIN_SESSION_SECRET_BYTES)
  end
  if session_secret.bytesize < MIN_SESSION_SECRET_BYTES
    raise ArgumentError, "SESSION_SECRET must be at least #{MIN_SESSION_SECRET_BYTES} bytes " \
                         "(generate one with: ruby -rsecurerandom -e 'puts SecureRandom.hex(64)')"
  end

  enable :sessions
  set :session_secret, session_secret
  set :sessions, httponly: true, same_site: :lax, secure: production?

  set :oauth_client, OAuth2::Client.new(
    settings.client_id,
    settings.client_secret,
    site: base_url,
    authorize_url: "#{base_url}/oauth/authorize",
    token_url: "#{base_url}/oauth/token",
    # oauth2 2.x defaults to HTTP Basic client auth; ID.me's docs send credentials in the request body.
    auth_scheme: :request_body
  )

  helpers do
    def h(text)
      Rack::Utils.escape_html(text.to_s)
    end

    def client
      settings.oauth_client
    end

    def error_page(status, message)
      halt status, <<~HTML
        <html>
          <body>
            <p>#{h message}</p>
            <p><a href="/">Start over</a></p>
          </body>
        </html>
      HTML
    end

    def valid_state?(expected, actual)
      !expected.to_s.empty? && !actual.to_s.empty? && Rack::Utils.secure_compare(expected, actual)
    end

    def stored_access_token
      token = session[:access_token]
      return unless token

      OAuth2::AccessToken.new(client, token, expires_at: session[:expires_at])
    end
  end

  get "/" do
    state = SecureRandom.urlsafe_base64(32)
    session[:oauth_state] = state
    auth_endpoint = client.auth_code.authorize_url(redirect_uri: settings.redirect_uri, scope: settings.scope,
                                                   state: state)

    # Link straight to the authorize URL (instead of the hosted ID.me button script) so the
    # per-session state parameter is always sent.
    alt = settings.use_mock ? "Verify with ID.me (mock)" : "Verify with ID.me"
    <<~HTML
      <html>
        <body>
          <a id="idme-button" href="#{h auth_endpoint}"><img src="/btn-alt-Troop.png" alt="#{alt}"></a>
        </body>
      </html>
    HTML
  end

  get "/callback" do
    expected_state = session.delete(:oauth_state)
    unless valid_state?(expected_state, params[:state])
      error_page 403, "Invalid OAuth state. Please try signing in again."
    end
    error_page 401, "Authorization failed: #{params[:error]}" if params[:error]
    error_page 400, "Missing authorization code." if params[:code].to_s.empty?

    begin
      token = client.auth_code.get_token(params[:code], redirect_uri: settings.redirect_uri)
    rescue OAuth2::Error, Faraday::Error => e
      logger.warn("Token exchange failed: #{e.class}: #{e.message}")
      error_page 502, "Could not complete sign in with ID.me. Please try again."
    end

    # Keep only what's needed to rebuild the token; the session lives in an encrypted cookie.
    session[:access_token] = token.token
    session[:expires_at] = token.expires_at

    redirect "/profile"
  end

  get "/profile" do
    # Retrieve the user's attributes with the access token saved in the session by "/callback"
    token = stored_access_token
    redirect "/" unless token

    if token.expired?
      session.clear
      redirect "/"
    end

    begin
      response = token.get(settings.attributes_url)
    rescue OAuth2::Error => e
      session.clear if e.response&.status == 401
      logger.warn("Attributes request failed: #{e.class}: #{e.message}")
      error_page 502, "Could not load your ID.me attributes. Please sign in again."
    rescue Faraday::Error => e
      logger.warn("Attributes request failed: #{e.class}: #{e.message}")
      error_page 502, "ID.me is unreachable right now. Please try again later."
    end

    begin
      attributes = JSON.parse(response.body)
    rescue JSON::ParserError
      error_page 502, "ID.me returned an unexpected response. Please try again later."
    end

    content_type :json
    JSON.pretty_generate(attributes)
  end

  run! if __FILE__ == $PROGRAM_NAME
end
