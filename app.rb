require "bundler/setup"
require "sinatra"
require "oauth2"

# Get this information by registering your app at https://developer.id.me
# Set IDME_BASE_URL=http://localhost:4568 to use the local mock (see mock_idme.rb)
client_id         = ENV.fetch("IDME_CLIENT_ID", "YOUR_CLIENT_ID")
client_secret     = ENV.fetch("IDME_CLIENT_SECRET", "YOUR_CLIENT_SECRET")
redirect_uri      = ENV.fetch("IDME_REDIRECT_URI", "http://localhost:4567/callback")
base_url          = ENV.fetch("IDME_BASE_URL", "https://api.id.me")
authorization_url = "#{base_url}/oauth/authorize"
token_url         = "#{base_url}/oauth/token"
attributes_url    = "#{base_url}/api/public/v3/attributes.json"
use_mock          = base_url != "https://api.id.me"

# Possible scope values: "military", "student", "responder", "teacher"
scope = ENV.fetch("IDME_SCOPE", use_mock ? "military" : "YOUR_SCOPE_VALUE")

# Enable sessions
use Rack::Session::Pool

# Instantiate OAuth 2.0 client
client = OAuth2::Client.new(client_id, client_secret, :authorize_url => authorization_url, :token_url => token_url, :scope => scope)

get "/" do
  auth_endpoint = client.auth_code.authorize_url(:redirect_uri => redirect_uri, :scope => scope)

  # The hosted ID.me button always points at api.id.me, so link directly when using the mock
  button = if use_mock
    %(<a id="idme-mock-button" href="#{Rack::Utils.escape_html(auth_endpoint)}"><img src="/btn-alt-Troop.png" alt="Verify with ID.me (mock)"></a>)
  else
    <<-HTML
      <span id="idme-wallet-button" data-scope="#{scope}" data-client-id="#{client_id}" data-redirect="#{redirect_uri}" data-response="code"></span>
      <script src="https://s3.amazonaws.com/idme/developer/idme-buttons/assets/js/idme-wallet-button.js"></script>
    HTML
  end

  <<-HTML
  <html>
    <body>
      #{button}
    </body>
  </html>
  HTML
end

get "/callback" do
  halt 401, "Authorization failed: #{Rack::Utils.escape_html(params[:error])}" if params[:error]

  # Exchange the code for an access token and save it in the session
  session[:oauth_token] = client.auth_code.get_token(params[:code], :redirect_uri => redirect_uri)

  redirect "/profile"
end

get "/profile" do
  # Retrieve the user's attributes with the access_token we saved in the session from the "/callback" route
  token = session[:oauth_token]
  redirect "/" unless token

  json_payload = token.get(attributes_url).body

  content_type "text/json"
  json_payload
end
