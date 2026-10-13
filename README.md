# ID.me Sample Ruby Web App

This is a sample seed Ruby Web App built with Sinatra

# Installation and Setup
In order to run the example you need to have `ruby` and `rubygems` installed.

First, install the required gems

```bash
gem install bundler
bundle install
```

Next, configure your oauth settings with environment variables (read by `app.rb`)

```bash
export IDME_CLIENT_ID="YOUR_CLIENT_ID"
export IDME_CLIENT_SECRET="YOUR_CLIENT_SECRET"
export IDME_SCOPE="YOUR_SCOPE_VALUE"
```

Start the server and view the app at [http://localhost:4567](http://localhost:4567)

```bash
ruby app.rb
```

# Running without ID.me credentials

`mock_idme.rb` is a local stand-in for the ID.me authorize, token and attributes endpoints, so the full
OAuth flow (sign in, `/callback`, `/profile`) can be demoed without an ID.me developer account.

```bash
ruby mock_idme.rb                                  # mock ID.me on http://localhost:4568
IDME_BASE_URL=http://localhost:4568 ruby app.rb    # app on http://localhost:4567
```

The mock accepts any client id/secret, issues single-use codes and returns sample `military` attributes.
