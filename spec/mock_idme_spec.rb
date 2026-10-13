# frozen_string_literal: true

RSpec.describe MockIdme do
  def app
    described_class
  end

  let(:authorize_params) do
    { client_id: "test-client", redirect_uri: "http://localhost:4567/callback", scope: "military", state: "xyz" }
  end

  it "echoes state back with the authorization code" do
    post "/oauth/authorize", authorize_params.merge(decision: "allow")

    query = URI.decode_www_form(URI(last_response.location).query).to_h
    expect(query["state"]).to eq("xyz")
    expect(query["code"]).not_to be_empty
  end

  it "echoes state back with access_denied" do
    post "/oauth/authorize", authorize_params.merge(decision: "deny")

    query = URI.decode_www_form(URI(last_response.location).query).to_h
    expect(query).to eq("error" => "access_denied", "state" => "xyz")
  end

  it "issues single-use codes" do
    post "/oauth/authorize", authorize_params.merge(decision: "allow")
    code = URI.decode_www_form(URI(last_response.location).query).to_h["code"]
    token_params = { grant_type: "authorization_code", code: code, client_id: "test-client",
                     redirect_uri: "http://localhost:4567/callback" }

    post "/oauth/token", token_params
    expect(last_response).to be_ok

    post "/oauth/token", token_params
    expect(last_response.status).to eq(400)
    expect(JSON.parse(last_response.body)["error"]).to eq("invalid_grant")
  end
end
