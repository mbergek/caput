# frozen_string_literal: true

require_relative 'remote'
require_relative 'config'

module Caput
  module Teardown
    extend self

    def run
      setup_user = Caput::Config['SETUP_USER']
      server = Caput::Config['SERVER']
      app_name = Caput::Config['APP_NAME']

      raise 'Missing configuration' unless setup_user && server && app_name

      remote = Caput::Remote.new(user: setup_user, host: server)

      puts "Tearing down application-specific server configuration on #{server} ..."
      remote.exec!(<<~BASH)
        sudo systemctl stop #{app_name}-puma || true
        sudo systemctl disable #{app_name}-puma || true
        sudo rm -f /etc/systemd/system/#{app_name}-puma.service || true
        sudo systemctl daemon-reload || true
        sudo rm -f /etc/nginx/sites-available/#{app_name} || true
        sudo rm -f /etc/nginx/sites-enabled/#{app_name} || true
        sudo nginx -t || true
        sudo systemctl reload nginx || true
      BASH

      puts "Teardown complete."
    end
  end
end
