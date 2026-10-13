# frozen_string_literal: true

# Local stand-in for the ID.me OAuth 2.0 endpoints used by app.rb, for demos without ID.me credentials.
# Run: ruby mock_idme.rb (port 4568), then: IDME_BASE_URL=http://localhost:4568 ruby app.rb
require "bundler/setup"
require "json"
require "securerandom"
require "sinatra/base"

class MockIdme < Sinatra::Base
  SUBGROUPS = {
    "military" => "Veteran",
    "student" => "Student",
    "responder" => "EMT",
    "teacher" => "Teacher"
  }.freeze

  CODES = {} # rubocop:disable Style/MutableConstant
  TOKENS = {} # rubocop:disable Style/MutableConstant

  set :port, ENV.fetch("MOCK_IDME_PORT", 4568).to_i

  helpers do
    def h(text)
      Rack::Utils.escape_html(text.to_s)
    end

    def redirect_with(redirect_uri, query)
      uri = URI(redirect_uri)
      uri.query = URI.encode_www_form(URI.decode_www_form(uri.query.to_s) + query.to_a)
      redirect uri.to_s
    end

    def oauth_error(status, error, description)
      halt status, { "content-type" => "application/json" }, { error: error, error_description: description }.to_json
    end
  end

  get "/oauth/authorize" do
    halt 400, "Missing client_id or redirect_uri" if params[:client_id].to_s.empty? || params[:redirect_uri].to_s.empty?
    halt 400, "Unsupported response_type" unless params[:response_type] == "code"

    <<~HTML
      <html>
        <head><title>ID.me (mock) - Sign in</title></head>
        <body style="font-family: sans-serif; max-width: 420px; margin: 40px auto;">
          <h2>ID.me (mock)</h2>
          <p><strong>#{h params[:client_id]}</strong> is requesting your <strong>#{h params[:scope]}</strong> verification status.</p>
          <form method="post" action="/oauth/authorize">
            <input type="hidden" name="client_id" value="#{h params[:client_id]}">
            <input type="hidden" name="redirect_uri" value="#{h params[:redirect_uri]}">
            <input type="hidden" name="scope" value="#{h params[:scope]}">
            <input type="hidden" name="state" value="#{h params[:state]}">
            <p><label>First name <input name="fname" value="Jane"></label></p>
            <p><label>Last name <input name="lname" value="Doe"></label></p>
            <p><label>Email <input name="email" value="jane.doe@example.com"></label></p>
            <button type="submit" name="decision" value="allow">Allow</button>
            <button type="submit" name="decision" value="deny">Deny</button>
          </form>
        </body>
      </html>
    HTML
  end

  post "/oauth/authorize" do
    state = params[:state].to_s.empty? ? {} : { state: params[:state] }
    unless params[:decision] == "allow"
      return redirect_with(params[:redirect_uri],
                           { error: "access_denied" }.merge(state))
    end

    code = SecureRandom.hex(16)
    CODES[code] = {
      client_id: params[:client_id],
      redirect_uri: params[:redirect_uri],
      scope: params[:scope].to_s,
      user: { uuid: SecureRandom.hex(16), fname: params[:fname], lname: params[:lname], email: params[:email] }
    }
    redirect_with(params[:redirect_uri], { code: code }.merge(state))
  end

  post "/oauth/token" do
    client_id = params[:client_id]
    auth = Rack::Auth::Basic::Request.new(request.env)
    client_id, _secret = auth.credentials if auth.provided? && auth.basic?

    unless params[:grant_type] == "authorization_code"
      oauth_error(400, "unsupported_grant_type", "Only authorization_code is supported")
    end

    grant = CODES.delete(params[:code].to_s)
    oauth_error(400, "invalid_grant", "Unknown or already used code") unless grant
    oauth_error(401, "invalid_client", "client_id does not match the code") unless grant[:client_id] == client_id
    unless grant[:redirect_uri] == params[:redirect_uri]
      oauth_error(400, "invalid_grant",
                  "redirect_uri does not match")
    end

    access_token = SecureRandom.hex(24)
    TOKENS[access_token] = grant

    content_type :json
    {
      access_token: access_token,
      token_type: "bearer",
      expires_in: 300,
      refresh_token: SecureRandom.hex(24),
      scope: grant[:scope]
    }.to_json
  end

  get "/api/public/v3/attributes.json" do
    token = request.env["HTTP_AUTHORIZATION"].to_s[/\ABearer (.+)\z/i, 1] || params[:access_token]
    grant = TOKENS[token.to_s]
    oauth_error(401, "invalid_token", "Missing or invalid access token") unless grant

    user = grant[:user]
    content_type :json
    {
      attributes: [
        { handle: "fname", name: "First Name", value: user[:fname] },
        { handle: "lname", name: "Last Name", value: user[:lname] },
        { handle: "email", name: "Email", value: user[:email] },
        { handle: "uuid", name: "Unique Identifier", value: user[:uuid] }
      ],
      status: grant[:scope].split(/[ ,]/).reject(&:empty?).map do |group|
        { group: group, subgroups: [SUBGROUPS.fetch(group, group.capitalize)], verified: true }
      end
    }.to_json
  end

  run! if __FILE__ == $PROGRAM_NAME
end
