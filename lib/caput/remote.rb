# frozen_string_literal: true

require 'net/ssh'
require 'net/scp'
require 'tempfile'

module Caput
  class Remote
    def initialize(user:, host:, ssh_options: {})
      @user = user
      @host = host
      @ssh_options = ssh_options
    end

    def exec!(cmd)
      exit_status = nil
      ssh_options = @options || {}

      Net::SSH.start(@host, @user, ssh_options) do |ssh|
        ssh.open_channel do |ch|
          ch.exec("bash -l") do |_, success|
            raise "could not start bash" unless success

            ch.on_data { |_, data| $stdout.print data }
            ch.on_extended_data { |_, _, data| $stderr.print data }
            ch.on_request("exit-status") { |_, data| exit_status = data.read_long }

            ch.send_data(cmd)
            ch.send_data("\nexit\n")
            ch.eof!
          end
        end

        ssh.loop
      end

      if exit_status != 0
        raise "Remote command failed (exit #{exit_status}): #{cmd}"
      end
    end

    def upload_content!(content, remote_path, mode: 0644)
      Tempfile.create do |f|
        f.binmode
        f.write(content)
        f.flush
        upload_file!(f.path, remote_path, mode: mode)
      end
    end

    def upload_file!(local_path, remote_path, mode: 0644)
      Net::SCP.start(@host, @user, **@ssh_options) do |scp|
        scp.upload!(local_path, remote_path)
      end
      exec!("sudo chmod #{sprintf('%o', mode)} #{remote_path}")
    end

    private

    def escape_for_bash(s)
      s.gsub('"', '"').gsub('$', '\$')
    end
  end
end
