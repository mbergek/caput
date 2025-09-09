# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "caput"
  spec.version       = begin
                         require_relative "lib/caput/version"
                         Caput::VERSION
                       end
  spec.authors       = ["Martin Bergek"]
  spec.email         = ["contact@spotwise.com"]
  spec.summary       = "Simplifies preparing Ubuntu servers for Rails apps with a Capistrano-friendly workflow"
  spec.description   = "Caput automates the repetitive steps required to make a Rails application ready to deploy on a fresh Ubuntu server. It ensures dependencies are installed, configures users, directories, and permissions, and sets up the environment for Capistrano deployments — all without requiring Passenger or container registries. With Caput, developers can enjoy the simplicity of Capistrano while minimising manual server setup."
  spec.homepage      = "https://github.com/mbergek/caput"
  spec.license       = "MIT"

  spec.files         = Dir["lib/**/*", "exe/*", "README.md", "LICENSE"]
  spec.bindir        = "exe"
  spec.executables   = ["caput"]
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 3.0"

  spec.add_dependency "thor", "~> 1.4"
  spec.add_dependency "net-ssh", "~> 7.3"
  spec.add_dependency "net-scp", "~> 4.1"
end
