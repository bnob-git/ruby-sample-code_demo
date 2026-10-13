# frozen_string_literal: true

RSpec.describe IdmeSampleApp do
  def app
    described_class
  end

  def authorize_url
    get "/"
    URI(button_href(last_response.body))
  end

  # Extract the ID.me button link without pulling in an HTML parser.
  def button_href(html)
    CGI.unescapeHTML(html[/id="idme-button" href="([^"]+)"/, 1])
  end

  def state_from(uri)
    URI.decode_www_form(uri.query).to_h.fetch("state")
  end

  # Simulates the user approving (or denying) the request on the mock ID.me page.
  def mock_idme_redirect(uri, decision: "allow")
    query = URI.decode_www_form(uri.query).to_h
    mock = Rack::MockRequest.new(MockIdme)
    form = { "fname" => "Jane", "lname" => "Doe", "email" => "jane.doe@example.com", "decision" => decision }
    response = mock.post("/oauth/authorize", params: query.merge(form))
    URI(response.location)
  end

  def callback_path(uri)
    "/callback?#{uri.query}"
  end

  describe "GET /" do
    it "links to the ID.me authorize URL with a random state stored in the session" do
      uri = authorize_url

      expect(last_response).to be_ok
      expect(uri.to_s).to start_with("http://localhost:4568/oauth/authorize?")
      params = URI.decode_www_form(uri.query).to_h
      expect(params).to include("client_id" => "test-client", "response_type" => "code", "scope" => "military",
                                "redirect_uri" => "http://localhost:4567/callback")
      expect(params["state"].length).to be >= 32
      expect(last_request.env["rack.session"][:oauth_state]).to eq(params["state"])
    end

    it "generates a new state on every visit" do
      first = state_from(authorize_url)
      second = state_from(authorize_url)

      expect(first).not_to eq(second)
    end
  end

  describe "OAuth round trip against the mock provider" do
    it "exchanges the code, stores only the token string and renders the profile" do
      redirect = mock_idme_redirect(authorize_url)

      get callback_path(redirect)
      expect(last_response).to be_redirect
      expect(URI(last_response.location).path).to eq("/profile")

      session = last_request.env["rack.session"]
      expect(session[:access_token]).to be_a(String)
      expect(session[:expires_at]).to be_a(Integer)
      expect(session[:oauth_state]).to be_nil

      follow_redirect!
      expect(last_response).to be_ok
      expect(last_response.content_type).to include("application/json")
      body = JSON.parse(last_response.body)
      expect(body["attributes"]).to include(include("handle" => "fname", "value" => "Jane"))
      expect(body["status"]).to eq([{ "group" => "military", "subgroups" => ["Veteran"], "verified" => true }])
    end

    it "sends client credentials in the token request body" do
      get callback_path(mock_idme_redirect(authorize_url))

      expect(a_request(:post, "http://localhost:4568/oauth/token")
        .with(body: hash_including("client_id" => "test-client", "client_secret" => "test-secret",
                                   "grant_type" => "authorization_code"))).to have_been_made.once
    end
  end

  describe "GET /callback state validation" do
    it "rejects a mismatched state without exchanging the code" do
      redirect = mock_idme_redirect(authorize_url)
      query = URI.decode_www_form(redirect.query).to_h.merge("state" => "forged")

      get "/callback?#{URI.encode_www_form(query)}"

      expect(last_response.status).to eq(403)
      expect(last_response.body).to include("Invalid OAuth state")
      expect(a_request(:post, "http://localhost:4568/oauth/token")).not_to have_been_made
      expect(last_request.env["rack.session"][:access_token]).to be_nil
    end

    it "rejects a missing state" do
      redirect = mock_idme_redirect(authorize_url)
      query = URI.decode_www_form(redirect.query).to_h.except("state")

      get "/callback?#{URI.encode_www_form(query)}"

      expect(last_response.status).to eq(403)
      expect(a_request(:post, "http://localhost:4568/oauth/token")).not_to have_been_made
    end

    it "rejects a callback when no state was issued for the session" do
      get "/callback?code=abc&state=abc"

      expect(last_response.status).to eq(403)
    end

    it "does not accept the same state twice" do
      redirect = mock_idme_redirect(authorize_url)
      get callback_path(redirect)
      expect(last_response).to be_redirect

      get callback_path(redirect)
      expect(last_response.status).to eq(403)
    end

    it "reports a denied authorization when the state is valid" do
      get callback_path(mock_idme_redirect(authorize_url, decision: "deny"))

      expect(last_response.status).to eq(401)
      expect(last_response.body).to include("Authorization failed: access_denied")
    end

    it "returns a friendly error when the code exchange fails" do
      uri = authorize_url
      get "/callback?#{URI.encode_www_form(code: "unknown", state: state_from(uri))}"

      expect(last_response.status).to eq(502)
      expect(last_response.body).to include("Could not complete sign in")
    end
  end

  describe "GET /profile" do
    def sign_in
      get callback_path(mock_idme_redirect(authorize_url))
    end

    it "redirects to / without a session" do
      get "/profile"

      expect(last_response).to be_redirect
      expect(URI(last_response.location).path).to eq("/")
    end

    it "redirects to / when the stored token has expired" do
      sign_in
      env "rack.session", last_request.env["rack.session"].to_h.merge("expires_at" => Time.now.to_i - 1)

      get "/profile"

      expect(last_response).to be_redirect
      expect(URI(last_response.location).path).to eq("/")
    end

    it "returns a friendly error and clears the session when the token is rejected" do
      sign_in
      MockIdme::TOKENS.clear

      get "/profile"

      expect(last_response.status).to eq(502)
      expect(last_response.body).to include("Could not load your ID.me attributes")
      expect(last_request.env["rack.session"][:access_token]).to be_nil
    end

    it "returns a friendly error when ID.me is unreachable" do
      sign_in
      stub_request(:get, "http://localhost:4568/api/public/v3/attributes.json").to_raise(Faraday::ConnectionFailed)

      get "/profile"

      expect(last_response.status).to eq(502)
      expect(last_response.body).to include("ID.me is unreachable")
    end
  end
end
