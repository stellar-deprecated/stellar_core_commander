# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'stellar_core_commander/version'

Gem::Specification.new do |spec|
  spec.name          = "stellar_core_commander"
  spec.version       = StellarCoreCommander::VERSION
  spec.authors       = ["Scott Fleckenstein"]
  spec.email         = ["nullstyle@gmail.com"]
  spec.summary       = %q{A helper gem for scripting stellar-core}
  spec.homepage      = ""
  spec.license       = "Apache 2.0"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency "stellar-base", "= 0.0.11"
  spec.add_dependency "slop", "~> 3.6.0"
  spec.add_dependency "faraday", "~> 0.9.1"
  spec.add_dependency "faraday_middleware", "~> 0.9.1"
  spec.add_dependency "pg", "~> 0.18.1"
  spec.add_dependency "sequel", "~> 4.21.0"
  spec.add_dependency "activesupport", ">= 4.0.0"
  spec.add_dependency "contracts", "~> 0.9"

  spec.add_development_dependency "bundler", "~> 1.7"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "pry"
end
