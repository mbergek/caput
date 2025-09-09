# frozen_string_literal: true

require 'thor'
require 'caput/config'
require 'caput/remote'
require 'caput/server'
require 'caput/local'
require 'caput/teardown'

module Caput
  class CLI < Thor
    desc 'init', 'Create a local caput.conf with sample settings'
    def init
      Caput::Config.init_config
    end

    desc 'server', 'Prepare the remote server for deployment'
    def server
      Caput::Config.load_config!
      Caput::Server.check_dependencies
      Caput::Server.prepare
    end

    desc 'local', 'Prepare the local Rails application for Capistrano'
    def local
      Caput::Config.load_config!
      Caput::Local.prepare
    end

    desc 'teardown', 'Remove application-specific server configuration'
    def teardown
      Caput::Config.load_config!
      Caput::Teardown.run
    end
  end
end
