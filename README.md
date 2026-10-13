# ID.me Sample Ruby Web App

This is a sample seed Ruby Web App built with Sinatra

# Installation and Setup
You need Ruby 3.4 (see `.ruby-version`) and Bundler.

First, install the required gems

```bash
bundle install
```

Next, configure your oauth settings with environment variables (read by `app.rb`). `dotenv` loads them from a
`.env` file, so you can copy `.env.example` to `.env` and fill it in.

```bash
export IDME_CLIENT_ID="YOUR_CLIENT_ID"
export IDME_CLIENT_SECRET="YOUR_CLIENT_SECRET"
export IDME_SCOPE="YOUR_SCOPE_VALUE"
export SESSION_SECRET="$(ruby -rsecurerandom -e 'puts SecureRandom.hex(64)')"  # required when RACK_ENV=production
```

Start the server and view the app at [http://localhost:4567](http://localhost:4567)

```bash
ruby app.rb          # or: bundle exec rackup -p 4567
```

# Running without ID.me credentials

`mock_idme.rb` is a local stand-in for the ID.me authorize, token and attributes endpoints, so the full
OAuth flow (sign in, `/callback`, `/profile`) can be demoed without an ID.me developer account.

```bash
ruby mock_idme.rb                                  # mock ID.me on http://localhost:4568
IDME_BASE_URL=http://localhost:4568 ruby app.rb    # app on http://localhost:4567
```

The mock accepts any client id/secret, issues single-use codes, echoes `state` and returns sample `military`
attributes.

# Tests and linting

```bash
bundle exec rspec     # exercises /, /callback and /profile against the in-process mock
bundle exec rubocop
```
