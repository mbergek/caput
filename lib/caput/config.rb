# frozen_string_literal: true

module Caput
  module Config
    CONFIG_FILE = 'caput.conf'

    def self.init_config
      return puts 'Configuration file already exists.' if File.exist?(CONFIG_FILE)
      File.write(CONFIG_FILE, <<~CONF)
        # Sample configuration for caput deployment

        # Name of the application. This name will be used for the nginx site as well
        # as for the Puma service definition.
        APP_NAME="myapp"

        # Setup user on the server. Note that this user should have passwordless sudo
        # access on the server. This user is only used while setting up the application.
        # This user must exist on the server, if it doesn't the script will notify the user
        # and exit.
        SETUP_USER="setup"

        # Deploy user on the server. This is the user that will own the application and also
        # run the Puma process that will run the application. If this user does not exist it
        # will be created.
        DEPLOY_USER="deploy"

        # Target server hostname or IP. This is the address to which the application will be
        # deployed. It does not, however, have to be the hostname of the application itself, and
        # in most cases it will not be.
        SERVER="example.com"

        # Domain for nginx site. This is the hostname that users will enter in their browsers
        # to reach the application. DNS configuration is assumed to have been done prior to
        # installing the application using this script.
        DOMAIN="www.example.com"

        # Ruby version to use with rbenv. This version will be installed via rbenv on the server.
        # It needs to match the RUBY version used by the Ruby on Rails application being deployed.
        RUBY_VERSION="3.2.2"

        # Path on the server where app will be deployed. This will be the root directory on the
        # server where the Ruby on Rails application will be deployed by Capistrano.
        DEPLOY_PATH="/var/www/myapp"

        # Git repository URL. This will be used to configure the Capistrano deployment files.
        REPO_URL="git@example.com:username/myapp.git"
      CONF
      puts "Created #{CONFIG_FILE}"
    end

    def self.load_config!
      unless File.exist?(CONFIG_FILE)
        abort "Configuration file #{CONFIG_FILE} not found! Run `caput init`."
      end
      @config = {}
      File.readlines(CONFIG_FILE).each do |line|
        next if line.strip.empty? || line.strip.start_with?('#')
        if line =~ /^(\w+)=(?:"(.*)"|'(.*)'|(.*))$/
          key = $1
          val = $2 || $3 || $4
          @config[key] = val.to_s
        end
      end
      # populate ENV for backwards compatibility
      @config.each { |k, v| ENV[k] = v }
    end

    def self.[](key)
      @config[key]
    end
  end
end
