# frozen_string_literal: true

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
      g.fixture_replacement :factory_bot, dir: "spec/factories"
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

def setup_bullet
  say('Setting up Bullet...', :green)

  insert_into_file(
    'config/environments/development.rb',
    after: "Rails.application.configure do\n"
  ) do
    <<~CONTENT
      # Bullet config
      config.after_initialize do
        Bullet.enable        = true
        Bullet.alert         = true
        Bullet.bullet_logger = true
        Bullet.console       = true
        Bullet.rails_logger  = true
        Bullet.add_footer    = true
      end
    CONTENT
  end
end

def add_gems
  say('Overwrite Gemfile with some useful gems...', :green)

  template('templates/Gemfile.erb', 'Gemfile', force: true)
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
    <<~CONTENT
      # set application queue adapter to sidekiq
      config.active_job.queue_adapter = :sidekiq
    CONTENT
  end

  insert_into_file(routes_file, before: 'Rails.application.routes.draw do') do
    <<~CONTENT
      require 'sidekiq/web'

    CONTENT
  end

  insert_into_file(routes_file, after: "Rails.application.routes.draw do\n") do
    <<~CONTENT
      authenticate :user, ->(u) { u.admin? } do
        mount Sidekiq::Web => '/sidekiq'
      end

    CONTENT
  end

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

def setup_devise
  say('Setting up Devise...', :green)

  generate('devise:install')

  environment(
    "config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }",
    env: 'development'
  )

  route "root to: 'home#index'"

  generate(
    :devise,
    'User',
    'first_name',
    'last_name',
    'username',
    'admin:boolean'
  )

  in_root do
    migration = Dir.glob('db/migrate/*').max_by { |f| File.mtime(f) }
    gsub_file(migration, /:admin/, ':admin, default: false')
  end

  insert_into_file('spec/factories/users.rb', after: "factory :user do\n") do
    <<~CONTENT
      first_name { Faker::Name.first_name }
      last_name { Faker::Name.last_name }
      username { Faker::Internet.username }
      admin { false }
    CONTENT
  end

  generate('devise:views')
end

def setup_rspec
  say('Setting up RSpec...', :green)

  generate('rspec:install')

  gsub_file(
    'spec/rails_helper.rb',
    "# Dir[Rails.root.join('spec', 'support', '**', '*.rb')].sort.each { |f| require f }"
  ) do
    <<~CONTENT
      Dir[Rails.root.join("spec/support/**/*.rb")].each { |f| require f }
    CONTENT
  end

  gsub_file(
    'spec/rails_helper.rb',
    '  config.fixture_path = "#{::Rails.root}/spec/fixtures"'
  ) do
    <<~CONTENT
      config.fixture_path = Rails.root.join("spec/fixtures")
    CONTENT
  end
end

def setup_factory_bot
  say('Setting up FactoryBot...', :green)

  create_file('spec/support/factory_bot.rb') do
    <<~CONTENT
      # frozen_string_literal: true

      RSpec.configure do |config|
        config.include FactoryBot::Syntax::Methods
      end
    CONTENT
  end
end

def setup_shoulda_matchers
  say('Setting up Shoulda Matchers...', :green)

  create_file('spec/support/shoulda_matchers.rb') do
    <<~CONTENT
      # frozen_string_literal: true

      Shoulda::Matchers.configure do |config|
        config.integrate do |with|
          with.test_framework :rspec
          with.library :rails
        end
      end
    CONTENT
  end
end

def setup_capybara
  say('Setting up Capybara...', :green)

  create_file('spec/support/capybara.rb') do
    <<~CONTENT
      # frozen_string_literal: true

      require "capybara/rails"
      require "capybara/rspec"

      RSpec.configure do |config|
        config.before(:each, type: :system) do
          # not needed if using selenium
          driven_by(:rack_test)
        end
      end
    CONTENT
  end
end

def setup_layouts
  application_layout = <<~LAYOUT
    <!DOCTYPE html>
    <html>
      <head>
        <title>
          <% if content_for?(:page_title) %>
            <%= content_for(:page_title) %>
          <% else %>
            #{app_name.camelize}
          <% end %>
        </title>

        <meta name="viewport" content="width=device-width,initial-scale=1">

        <%= csrf_meta_tags %>
        <%= csp_meta_tag %>

        <%= stylesheet_link_tag "tailwind", "inter-font", "data-turbo-track": "reload" %>
        <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>

        <%= javascript_importmap_tags %>
      </head>

      <body>
        <main class="container mx-auto mt-28 px-5 flex">
          <%= yield %>
        </main>
      </body>
    </html>
  LAYOUT

  remove_file('app/views/layouts/application.html.erb')
  create_file('app/views/layouts/application.html.erb', application_layout)
end

def setup_models
  say('Setting up model + spec...', :green)

  create_file('app/models/user.rb', force: true) do
    <<~CONTENT
      # frozen_string_literal: true

      class User < ApplicationRecord
        # Include default devise modules. Others available are:
        # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
        devise :database_authenticatable, :registerable, :recoverable, :rememberable, :validatable

        validates :username, presence: true
        validates :email, presence: true
      end
    CONTENT
  end

  create_file('spec/models/user_spec.rb', force: true) do
    <<~CONTENT
      # frozen_string_literal: true

      require "rails_helper"

      RSpec.describe User, type: :model do
        describe "validations" do
          it { is_expected.to validate_presence_of(:username) }
          it { is_expected.to validate_presence_of(:email) }
        end
      end
    CONTENT
  end
end

def setup_system_specs
  say('Setting some basic system specs...', :green)

  # create_file('spec/system/.keep')

  template(
    'templates/spec/system/users/logins_spec.rb',
    'spec/system/users/logins_spec.rb'
  )
  template(
    'templates/spec/system/users/registrations_spec.rb',
    'spec/system/users/registrations_spec.rb'
  )
end

def setup_rubocop
  say('Setting up Rubocop...', :green)

  template('templates/rubocop/rubocop_config.yml.erb', '.rubocop.yml')
end

def setup_overcommit
  say('Setting up Overcommit...', :green)

  run 'overcommit --install'
  create_file('.overcommit.yml', force: true) do
    <<~CONTENT
      #   TrailingWhitespace:
      #     enabled: true
      #     exclude:
      #       - "**/db/structure.sql" # Ignore trailing whitespace in generated files

      # PostCheckout:
      #   ALL: # Special hook name that customizes all hooks of this type
      #     quiet: true # Change all post-checkout hooks to only display output on failure

      #   IndexTags:
      #     enabled: true # Generate a tags file with `ctags` each time HEAD changes

      ---
      PreCommit:
        RuboCop:
          enabled: true
          command: ["bundle", "exec", "rubocop"]
          on_warn: fail
          problem_on_unmodified_line: ignore # run RuboCop only on
    CONTENT
  end

  run 'overcommit --sign'
end

def setup_annotate
  generate('annotate:install')

  template(
    'templates/annotate/annotate_rake_tak.rb',
    'lib/tasks/auto_annotate_models.rake',
    force: true
  )
end

source_paths

add_gems

after_bundle do
  template('templates/asdf/tool-versions.erb', '.tool-versions')

  git(:init)
  git(add: '.')
  git(commit: %( -m 'Initial commit' ))

  setup_config_application

  git(add: '.')
  git(commit: %( -m 'Configure application settings' ))

  setup_bullet

  git(add: '.')
  git(commit: %( -m 'Configure bullet' ))

  setup_db

  git(add: '.')
  git(commit: %( -m 'Configure database' ))

  setup_sidekiq

  git(add: '.')
  git(commit: %( -m 'Configure sidekiq' ))

  setup_docker_files

  git(add: '.')
  git(commit: %( -m 'Configure docker' ))

  setup_devise

  git(add: '.')
  git(commit: %( -m 'Configure devise' ))

  generate(:controller, 'Home', 'index')
  generate(:views, 'Home', 'index')

  git(add: '.')
  git(commit: %( -m 'Scaffold home' ))

  setup_rspec

  git(add: '.')
  git(commit: %( -m 'Configure RSpec' ))

  setup_system_specs

  git(add: '.')
  git(commit: %( -m 'Add user system specs' ))

  setup_factory_bot

  git(add: '.')
  git(commit: %( -m 'Configure FactoryBot for rails' ))

  setup_shoulda_matchers

  git(add: '.')
  git(commit: %( -m 'Configure shoulda-matchers' ))

  setup_capybara

  git(add: '.')
  git(commit: %( -m 'Configure Capybara' ))

  setup_layouts

  git(add: '.')
  git(commit: %( -m 'Tweak application layout' ))

  setup_models

  git(add: '.')
  git(commit: %( -m 'Tweak Models' ))

  setup_rubocop

  git(add: '.')
  git(commit: %( -m 'Configure Rubocop' ))

  setup_overcommit

  git(add: '.')
  git(commit: %( -m 'Configure overcommit' ))

  run('bundle exec rubocop -A')

  setup_annotate

  git(add: '.')
  git(commit: %( -m 'Configure Annotate' ))

  git(add: '.')
  git(commit: %( -m 'Run Rubocop in repo' ))

  say('Done! 🎉', :green)
end
