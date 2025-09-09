# frozen_string_literal: true

require 'fileutils'
require_relative 'config'

module Caput
  module Local
    extend self

    def prepare
      app_name = Caput::Config['APP_NAME']
      repo_url = Caput::Config['REPO_URL']
      deploy_path = Caput::Config['DEPLOY_PATH']
      ruby_version = Caput::Config['RUBY_VERSION']
      server = Caput::Config['SERVER']
      deploy_user = Caput::Config['DEPLOY_USER']

      puts "Preparing local Rails application..."

      unless bundle_has?('capistrano')
        puts "Adding Capistrano gems to Gemfile..."
        system('bundle add capistrano capistrano-rails capistrano-rbenv')
      end

      puts "Running bundle install..."
      system('bundle install')

      unless File.exist?('Capfile')
        puts "Running 'cap install' to create Capfile and config directories..."
        system('bundle exec cap install')
      end

      ensure_file_contains('Capfile', "require 'capistrano/rails'")
      ensure_file_contains('Capfile', "require 'capistrano/rbenv'")

      FileUtils.mkdir_p('config/deploy')
      deploy_rb = 'config/deploy.rb'
      backup_file(deploy_rb)
      File.open(deploy_rb, 'a') do |f|
        f.puts <<~DEPLOY

          set :application, "#{app_name}"
          set :repo_url, "#{repo_url}"
          set :deploy_to, "#{deploy_path}"
          set :rbenv_type, :user
          set :rbenv_ruby, "#{ruby_version}"
          set :puma_bind, "unix://#{deploy_path}/shared/tmp/sockets/puma.sock"
          set :puma_pid, "#{deploy_path}/shared/tmp/pids/puma.pid"
          ask :branch, `git rev-parse --abbrev-ref HEAD`.chomp
          set :linked_files, fetch(:linked_files, []).push('config/master.key')
        DEPLOY
      end

      File.open('config/deploy/production.rb', 'a') do |f|
        f.puts "server \"#{server}\", user: \"#{deploy_user}\", roles: %w{app db web}"
      end

      FileUtils.mkdir_p(['tmp/pids', 'tmp/sockets', 'log'])

      puts "\nLocal application prepared. You can now run:\n\n  bundle exec cap production deploy"
    end

    def bundle_has?(gem_name)
      out = `bundle list --name-only 2>/dev/null || true`
      out.split("\n").any? { |l| l.include?(gem_name) }
    end

    def ensure_file_contains(path, line)
      return unless File.exist?(path)
      content = File.read(path)
      unless content.include?(line)
        File.open(path, 'a') { |f| f.puts line }
      end
    end

    def backup_file(path)
      return unless File.exist?(path)
      bak = "#{path}.bak"
      FileUtils.cp(path, bak)
    end
  end
end
