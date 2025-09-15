# frozen_string_literal: true

require_relative 'remote'
require_relative 'config'

module Caput
  module Server
    extend self

    def check_dependencies
      setup_user  = Caput::Config['SETUP_USER']
      server      = Caput::Config['SERVER']

      remote = Caput::Remote.new(user: setup_user, host: server)

      puts "\nValidating server dependencies..."

      begin
        # Check for MySQL server
        remote.exec!(<<~BASH)
          if ! command -v mysql >/dev/null 2>&1; then
            echo "ERROR: MySQL client/server not installed" >&2
            exit 1
          fi
          if ! systemctl is-active --quiet mysql && ! systemctl is-active --quiet mariadb; then
            echo "ERROR: MySQL/MariaDB service is not running" >&2
            exit 1
          fi
        BASH
        
        # Check for nginx
        remote.exec!(<<~BASH)
          if ! command -v nginx >/dev/null 2>&1; then
            echo "ERROR: nginx not installed" >&2
            exit 1
          fi
          if ! systemctl is-active --quiet nginx; then
            echo "ERROR: nginx service is not running" >&2
            exit 1
          fi
        BASH

      rescue RuntimeError => e
        exit 1          # stop Caput immediately
      end

      puts "All dependencies satisfied."
    end

    def prepare
      setup_user  = Caput::Config['SETUP_USER']
      deploy_user = Caput::Config['DEPLOY_USER']
      server      = Caput::Config['SERVER']
      app_name    = Caput::Config['APP_NAME']
      domain      = Caput::Config['DOMAIN']
      deploy_path = Caput::Config['DEPLOY_PATH']
      ruby_version = Caput::Config['RUBY_VERSION']

      raise 'Missing configuration: run `caput init` and edit caput.conf' unless setup_user && server && deploy_user && app_name

      check_sudo!(setup_user, server)

      remote = Caput::Remote.new(user: setup_user, host: server)

      puts "\nInstalling system dependencies on remote..."
      remote.exec!(<<~BASH)
        sudo apt-get update || true
        sudo apt-get install -y git curl build-essential libssl-dev libreadline-dev zlib1g-dev libffi-dev libyaml-dev libgdbm-dev libncurses-dev libdb-dev libsqlite3-dev libgmp-dev libbz2-dev autoconf bison pkg-config liblzma-dev libxml2-dev libxslt1-dev libcurl4-openssl-dev nginx || true
      BASH

      puts "\nVerify deploy user account..."
      remote.exec!(<<~BASH)
        if getent passwd #{deploy_user} >/dev/null 2>&1; then
          echo "Deploy user already exists"
        else
          echo "Creating deploy user #{deploy_user}"
          sudo adduser --disabled-password --gecos "" #{deploy_user}
        fi
      BASH

      puts "\nEnsure deploy authorized_keys and home..."
      remote.exec!(<<~BASH)
        DEPLOY_HOME="$(getent passwd #{deploy_user} | cut -d: -f6)"
        DEPLOY_SSH_DIR="$DEPLOY_HOME/.ssh"
        SETUP_HOME="$(getent passwd #{setup_user} | cut -d: -f6)"

        sudo mkdir -p "$DEPLOY_SSH_DIR"
        sudo chown #{deploy_user}:#{deploy_user} "$DEPLOY_SSH_DIR"
        sudo chmod 700 "$DEPLOY_SSH_DIR"

        AUTH_KEYS="$DEPLOY_SSH_DIR/authorized_keys"
        if [ ! -s "$AUTH_KEYS" ]; then
          echo "Copying authorized_keys from setup user"
          sudo cp "$SETUP_HOME/.ssh/authorized_keys" "$AUTH_KEYS" || true
          sudo chown #{deploy_user}:#{deploy_user} "$AUTH_KEYS" || true
          sudo chmod 600 "$AUTH_KEYS" || true
        else
          echo "Authorized keys already present"
        fi
      BASH

      puts "\nCreate deploy directories..."
      remote.exec!(<<~BASH)
        if [ -d "#{deploy_path}" ]; then
          echo "Deploy directories already exist"
        else
          sudo mkdir -p \
              "#{deploy_path}/shared/tmp/pids" \
              "#{deploy_path}/shared/tmp/sockets" \
              "#{deploy_path}/shared/log" \
              "#{deploy_path}/shared/storage" \
              "#{deploy_path}/shared/config"
          sudo chown -R #{deploy_user}:#{deploy_user} "#{deploy_path}"
        fi
      BASH

      puts "Upload master key if it exists"
      master_path = "config/master.key"
      if File.exist?(master_path)
        remote.upload_file!(master_path, "/tmp/master.key")
        remote.exec!("sudo mv /tmp/master.key #{deploy_path}/shared/config/master.key")
        remote.exec!("sudo chmod 0400 #{deploy_path}/shared/config/master.key")
      else
        puts "Note: No master key exists in local directory"
      end

      puts "\nCreate MySQL user if it doesn't exist"

      # Get username and password from the local configuration file
      require 'active_support'
      require 'active_support/encrypted_configuration'
      require 'yaml'
      rails_root = Dir.pwd
      credentials_path = File.join(rails_root, 'config', 'credentials.yml.enc')
      master_key_path = File.join(rails_root, 'config', 'master.key')
      master_key = ENV['RAILS_MASTER_KEY'] || (File.exist?(master_key_path) && File.read(master_key_path).strip)
      raise "Master key not found in ENV['RAILS_MASTER_KEY'] or #{master_key_path}" unless master_key

      # Create encrypted configuration
      conf = ActiveSupport::EncryptedConfiguration.new(
        config_path: credentials_path,
        key_path: master_key_path,
        env_key: 'RAILS_MASTER_KEY',
        raise_if_missing_key: true
      )

      creds = YAML.safe_load(conf.read)
      mysql_database = creds.dig('mysql', 'database')
      mysql_username = creds.dig('mysql', 'username')
      mysql_password = creds.dig('mysql', 'password')

      sql = <<~SQL
        CREATE DATABASE IF NOT EXISTS #{mysql_database};
        CREATE USER IF NOT EXISTS #{mysql_username}@localhost IDENTIFIED BY '#{mysql_password}';
        GRANT ALL PRIVILEGES ON #{mysql_database}.* TO #{mysql_username}@localhost;
        FLUSH PRIVILEGES;
      SQL

      # Escape quotes for bash
      escaped_sql = sql.strip.gsub('"', '\"').gsub('$', '\$')

      # Build the full command to run on the remote server
     cmd = %Q(sudo mysql -e "#{escaped_sql}")
     remote.exec!(cmd)

      puts "\nInstall Nginx site config..."
      nginx_conf = <<~NGINX
        server {
            listen 80;
            server_name #{domain};

            root #{deploy_path}/current/public;

            location / {
                try_files $uri @puma;
            }

            location @puma {
                proxy_pass http://unix:#{deploy_path}/shared/tmp/sockets/puma.sock;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header Host $http_host;
                proxy_redirect off;
            }

            error_page 500 502 503 504 /500.html;
        }
      NGINX

      remote.upload_content!(nginx_conf, "/tmp/#{app_name}.nginx")
      remote.exec!(<<~BASH)
        sudo mv /tmp/#{app_name}.nginx /etc/nginx/sites-available/#{app_name}
        sudo ln -sf /etc/nginx/sites-available/#{app_name} /etc/nginx/sites-enabled/#{app_name}
        sudo nginx -t
        sudo systemctl reload nginx
      BASH

      puts "\nSetup Puma systemd service..."
      service_file = <<~SERVICE
        [Unit]
        Description=Puma HTTP Server for #{app_name}
        After=network.target

        [Service]
        Type=simple
        User=#{deploy_user}
        WorkingDirectory=#{deploy_path}/current
        Environment="RAILS_ENV=production"
        Environment="RACK_ENV=production"
        ExecStart=#{deploy_path}/shared/bin/start_puma.sh
        Restart=always

        [Install]
        WantedBy=multi-user.target
      SERVICE

      remote.upload_content!(service_file, "/tmp/#{app_name}-puma.service")
      remote.exec!(<<~BASH)
        sudo mv /tmp/#{app_name}-puma.service /etc/systemd/system/#{app_name}-puma.service
        sudo systemctl daemon-reload
        sudo systemctl enable #{app_name}-puma
      BASH

      puts "Create a simple puma.rb and start script in shared (if missing)"
      puma_rb = <<~PUMA
        threads 0,16
        workers 1
        app_dir = "#{deploy_path}/current"
        shared_dir = "#{deploy_path}/shared"
        bind "unix://\#{shared_dir}/tmp/sockets/puma.sock"
        pidfile "\#{shared_dir}/tmp/pids/puma.pid"
        stdout_redirect "\#{shared_dir}/log/puma.stdout.log", "\#{shared_dir}/log/puma.stderr.log", true
      PUMA

      start_sh = <<~SH
        #!/bin/bash
        export RBENV_ROOT="$HOME/.rbenv"
        export PATH="$RBENV_ROOT/bin:$PATH"
        eval "$(rbenv init -)"
        cd #{deploy_path}/current || exit 1
        exec $RBENV_ROOT/shims/bundle exec puma -C #{deploy_path}/shared/puma.rb
      SH

      remote.upload_content!(puma_rb, "/tmp/puma.rb")
      remote.exec!("sudo mv -f /tmp/puma.rb #{deploy_path}/shared/puma.rb || true")
      remote.upload_content!(start_sh, "/tmp/start_puma.sh")
      remote.exec!(<<~BASH)
        sudo mkdir -p #{deploy_path}/shared/bin
        sudo mv -f /tmp/start_puma.sh #{deploy_path}/shared/bin/start_puma.sh
        sudo chown -R #{deploy_user}:#{deploy_user} #{deploy_path}/shared
        sudo chmod +x #{deploy_path}/shared/bin/start_puma.sh
      BASH

      puts "\nInstall rbenv and Ruby for deploy user..."
      deploy_remote = Caput::Remote.new(user: deploy_user, host: server)
      deploy_remote.exec!(<<~BASH)
        RBENV_DIR="$HOME/.rbenv"
        if [ ! -d "$RBENV_DIR" ]; then
          git clone https://github.com/rbenv/rbenv.git "$RBENV_DIR"
          mkdir -p "$RBENV_DIR/plugins"
          git clone https://github.com/rbenv/ruby-build.git "$RBENV_DIR/plugins/ruby-build"
        else
          echo "rbenv already installed"
        fi

        export RBENV_ROOT="$RBENV_DIR"
        export PATH="$RBENV_ROOT/bin:$PATH"
        eval "$(rbenv init -)"

        if ! rbenv versions | grep -q "#{ruby_version}"; then
          rbenv install "#{ruby_version}" || true
        else
          echo "Ruby #{ruby_version} already installed"
        fi

        rbenv global "#{ruby_version}"
        rbenv rehash

        if ! grep -q 'rbenv init' ~/.bashrc; then
          echo 'export RBENV_ROOT=\"$HOME/.rbenv\"' >> ~/.bashrc
          echo 'export PATH=\"$RBENV_ROOT/bin:$PATH\"' >> ~/.bashrc
          echo 'eval \"$(rbenv init -)\"' >> ~/.bashrc
        fi

        gem install bundler --no-document || true
        rbenv rehash
      BASH

      puts "\nServer preparation complete."
      puts "\nBefore deploying, please verify that the deploy user has access to the the code repository."
    end

    def check_sudo!(user, server)
      cmd = %{ssh #{user}@#{server} "sudo -n true"}
      puts "Checking passwordless sudo for #{user}@#{server}..."
      success = system(cmd)
      unless success && $?.exitstatus == 0
        abort <<~MSG
          Warning: Setup user #{user} does not have passwordless sudo on #{server}.
          Example sudoers entry:
            #{user} ALL=(ALL) NOPASSWD:ALL
        MSG
      end
    end
  end
end
