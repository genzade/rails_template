#   Usage:
#     rails new myapp
#       --database=postgresql \
#       --skip-jbuilder \
#       --skip-test \
#       --css=tailwind \
#       --template=path/to/this/template.rb

def source_paths
  [__dir__]
end

def setup_config_application
  say('Setting up config/application.rb...', :green)

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

  gsub_file('config/application.rb', target, content)
end

def add_gems
  say('Adding some useful gems...', :green)

  gem('devise', '~> 4.9', '>= 4.9.2')
  gem('pg', '~> 1.1')
  gem('sidekiq', '~> 7.0', '>= 7.0.9')
end

def setup_devise
  say('Setting up Devise...', :green)

end

def setup_db
  say('Setting up database...', :green)

  inside 'config' do
    remove_file('database.yml')
    create_file('database.yml') do
      <<~CONTENT
        ---
        default: &default
          adapter: postgresql
          encoding: unicode
          host: <%= ENV.fetch("DATABASE_HOST", "localhost") %>
          min_messages: warning
          password: <%= ENV.fetch("DATABASE_PASSWORD", "") %>
          pool: <%= ENV.fetch("RAILS_MAX_THREADS", 5) %>
          port: <%= ENV.fetch("DATABASE_PORT", 5432) %>
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
          username: #{app_name}
      CONTENT
    end
  end
end

def setup_sidekiq
  say('Setting up Sidekiq...', :green)

  routes_file = 'config/routes.rb'

  environment('config.active_job.queue_adapter = :test', env: :test)

  insert_into_file('config/application.rb', before: /^  end\n/) do
    <<-CONTENT

    # set application queue adapter to sidekiq
    config.active_job.queue_adapter = :sidekiq
    CONTENT
  end

  insert_into_file(routes_file, "require 'sidekiq/web'\n\n", before: 'Rails.application.routes.draw do')

  content = <<-CONTENT
  authenticate :user, ->(u) { u.admin? } do
    mount Sidekiq::Web => '/sidekiq'
  end
  CONTENT

  insert_into_file(routes_file, "#{content}\n", after: "Rails.application.routes.draw do\n")

  create_file('config/initializers/sidekiq.rb') do
    <<~SIDEKIQ
      # frozen_string_literal: true

      Sidekiq.configure_server do |config|
        config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1") }
      end

      Sidekiq.configure_client do |config|
        config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1") }
      end
    SIDEKIQ
  end
end

def setup_docker_files
  say('Setting up Docker files...', :green)

  copy_file('templates/docker_files/docker-entrypoint', 'bin/docker-entrypoint')
  chmod('bin/docker-entrypoint', 0o755)
  template('templates/docker_files/Dockerfile.erb', 'Dockerfile')
  template('templates/docker_files/docker-compose.yml.erb', 'docker-compose.yml')
end

source_paths

add_gems

after_bundle do
  git(:init)
  git(add: '.')
  git(commit: %( -m 'Initial commit' ))

  setup_config_application

  git(add: '.')
  git(commit: %( -m 'Configure application settings' ))

  setup_db

  git(add: '.')
  git(commit: %( -m 'Configure database' ))

  setup_sidekiq

  git(add: '.')
  git(commit: %( -m 'Configure sidekiq' ))

  # setup_docker_files

  # git(add: '.')
  # git(commit: %( -m 'Configure docker' ))

  setup_devise
end
