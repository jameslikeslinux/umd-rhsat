# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'umd/rhsat/version'

Gem::Specification.new do |spec|
  spec.name          = "umd-rhsat"
  spec.version       = Umd::Rhsat::VERSION
  spec.authors       = ["James T. Lee"]
  spec.email         = ["jtl@umd.edu"]
  spec.description   = "Ruby library for Red Hat Network Satellite"
  spec.summary       = "Ruby library for Red Hat Network Satellite"
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "redcarpet"
  spec.add_development_dependency "yard"
  spec.add_development_dependency "rspec", "~> 2.6"

  spec.add_dependency "logging", "~> 1.8.1"
end
