=begin
  Usage:
    rails new myapp
      --database=postgresql \
      --skip-jbuilder \
      --skip-test \
      --css=tailwind \
      --template=path/to/this/template.rb
=end

def source_paths
  [File.expand_path(File.dirname(__FILE__))]
end

def add_gems
  say "Adding some useful gems...", :green

  gem "devise", "~> 4.9", ">= 4.9.2"
  gem "pg", "~> 1.1"
  gem "sidekiq", "~> 7.0", ">= 7.0.9"
end

def setup_config_application
  say "Setting up config/application.rb...", :green

  target = <<-TARGET
    # Don't generate system test files.
    config.generators.system_tests = nil
  TARGET

  content = <<-CONTENT
    # for scaffolding
    config.generators do |g|
      g.skip_routes true
      g.helper false
      g.assets false
      g.test_framework :rspec, fixture: false
      g.helper_specs false
      g.controller_specs false
      g.system_tests false
      g.view_specs false
    end

    # GZip all responses
    # TODO: remove if using nginx in deployment
    config.middleware.use Rack::Deflater
  CONTENT

  gsub_file("config/application.rb", target, content)
end

def setup_devise
  say "Setting up Devise...", :green
end

def setup_db
  say "Setting up database...", :green

  inside "config" do
    remove_file "database.yml"
    create_file "database.yml" do
      <<~CONTENT
        ---
        default: &default
          adapter: postgresql
          encoding: unicode
          host: <%= ENV.fetch("DATABASE_HOST", "localhost") %>
          min_messages: warning
          password: <%= ENV.fetch("DATABASE_PASSWORD", "") %>
          pool: <%= ENV.fetch("RAILS_MAX_THREADS", 5) %>
          port: <%= ENV.fetch("DATABASE_PORT", "5432") %>
          timeout: 5000
          username: <%= ENV.fetch("DATABASE_USER", "postgres") %>

        development:
          <<: *default
          database: #{app_name}_development

        test:
          <<: *default
          database: #{app_name}_test

        ---
        production:
          <<: *default
          database: #{app_name}_production
          password: <%= ENV["#{app_name.upcase}_DATABASE_PASSWORD"] %>
          username: <%= #{app_name} %>
      CONTENT
    end
  end
end

def setup_sidekiq
  say "Setting up Sidekiq...", :green

  routes_file = "config/routes.rb"

  environment("config.active_job.queue_adapter = :test", env: :test)

  insert_into_file('config/application.rb', before: /^  end\n/) do
    <<-CONTENT

    # set application queue adapter to sidekiq
    config.active_job.queue_adapter = :sidekiq
    CONTENT
  end

  insert_into_file(
    routes_file,
    "require 'sidekiq/web'\n\n",
    before: "Rails.application.routes.draw do"
  )

  content = <<-CONTENT
  authenticate :user, ->(u) { u.admin? } do
    mount Sidekiq::Web => '/sidekiq'
  end
  CONTENT

  insert_into_file(
    routes_file,
    "#{content}\n",
    after: "Rails.application.routes.draw do\n"
  )

  file("config/initializers/sidekiq.rb", <<~SIDEKIQ)
    # frozen_string_literal: true

    Sidekiq.configure_server do |config|
      config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1") }
    end

    Sidekiq.configure_client do |config|
      config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1") }
    end
  SIDEKIQ
end

def setup_docker_files
  say "Setting up Docker files...", :green

  inside "bin" do
    create_file "docker-entrypoint.sh" do
      <<~CONTENT
        #!/bin/sh

        # exit script if there is an error
        set -e

        echo "ENVIRONMENT: $RAILS_ENV"

        # If running the rails server then create or migrate existing database
        if [ "${*}" = "./bin/rails server" ]; then
          bin/rails db:prepare
        fi

        # remove pid file from previous session
        rm -f "$APP_PATH"/tmp/pids/server.pid

        exec "${@}"
      CONTENT
    end
  end

  file("Dockerfile", <<~DOCKERFILE)
    # syntax = docker/dockerfile:1

    # Make sure RUBY_VERSION matches the Ruby version in .ruby-version and Gemfile
    ARG RUBY_VERSION=3.1.2
    FROM registry.docker.com/library/ruby:$RUBY_VERSION-slim as base

    ENV APP_PATH /#{app_name}_app
    ENV RAILS_PORT 3000

    # Rails app lives here
    WORKDIR $APP_PATH

    # # Set production environment
    # ENV RAILS_ENV="production" \
    #   BUNDLE_DEPLOYMENT="1" \
    #   BUNDLE_PATH="/usr/local/bundle" \
    #   BUNDLE_WITHOUT="development"

    # Throw-away build stage to reduce size of final image
    FROM base as build

    # Install packages needed to build gems
    RUN apt-get update -qq && \
      apt-get install --no-install-recommends -y build-essential git libpq-dev libvips pkg-config

    # Install application gems
    COPY Gemfile Gemfile.lock ./
    RUN bundle install && \
      rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
      bundle exec bootsnap precompile --gemfile


    # Copy application code
    COPY . .

    # Precompile bootsnap code for faster boot times
    RUN bundle exec bootsnap precompile app/ lib/

    # # Precompiling assets for production without requiring secret RAILS_MASTER_KEY
    # RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

    # Final stage for app image
    FROM base

    # Install packages needed for deployment
    RUN apt-get update -qq && \
      apt-get install --no-install-recommends -y libvips postgresql-client && \
      rm -rf /var/lib/apt/lists /var/cache/apt/archives

    # Copy built artifacts: gems, application
    COPY --from=build /usr/local/bundle /usr/local/bundle
    COPY --from=build $APP_PATH $APP_PATH

    # Run and own only the runtime files as a non-root user for security
    RUN useradd rails --home $APP_PATH --shell /bin/bash && \
      chown -R rails:rails db log storage tmp

    USER rails:rails

    # Entrypoint prepares the database.
    ENTRYPOINT ["./bin/docker-entrypoint"]

    # Start the server by default, this can be overwritten at runtime
    EXPOSE $RAILS_PORT

    CMD ["./bin/rails", "server"]
  DOCKERFILE

  file("docker-compose.yml", <<~DOCKERCOMPOSE)
    ---
    version: "3.7"

    services:
      app:
        build:
          context: .

        command: bin/rails server --port 3000 --binding 0.0.0.0
        entrypoint: "./bin/docker-entrypoint"
        image: #{app_name}_app
        ports:
          - "127.0.0.1:3000:3000"
          - "127.0.0.1:7000:7000"
          - "127.0.0.1:5432:5432"
        depends_on:
          - db
          - redis
        environment:
          DATABASE_HOST: "db"
          POSTGRES_USER: "postgres"
          # # uncomment for production
          # RAILS_ENV: production
          RAILS_LOG_TO_STDOUT: 1
          RAILS_SERVE_STATIC_FILES: 1
          REDIS_URL: redis://redis:6379/1

        networks:
          - default
        volumes:
          - .:/#{app_name}_app

      db:
        environment:
          POSTGRES_HOST_AUTH_METHOD: trust
          # See: https://github.com/docker-library/postgres/pull/658. Alternatively,
          #   - POSTGRES_USER=postgres
          #   - POSTGRES_PASSWORD=postgres
        image: postgres:15
        ports:
          - "54320:5432"
        restart: always
        volumes:
          - db_data:/var/lib/postgresql/data

      redis:
        image: redis:7.0.10-alpine
        ports:
          - "6379:6379"

      sidekiq:
        build: .
        command: bundle exec sidekiq
        depends_on:
          - "db"
          - "redis"
        environment:
          REDIS_URL: redis://redis:6379/12
        volumes:
          - ".:/project"
          - "/project/tmp" # don't mount tmp directory

    volumes:
      db_data:
  DOCKERCOMPOSE
end

source_paths

add_gems

after_bundle do
  git :init
  git add: "."
  git commit: %Q{ -m 'Initial commit' }

  setup_config_application

  git add: "."
  git commit: %Q{ -m 'Configure application settings' }

  setup_db

  git add: "."
  git commit: %Q{ -m 'Configure database' }

  setup_sidekiq

  git add: "."
  git commit: %Q{ -m 'Configure sidekiq' }

  setup_docker_files

  git add: "."
  git commit: %Q{ -m 'Configure docker' }

  setup_devise
end
