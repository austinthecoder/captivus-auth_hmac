# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'captivus/auth_hmac/version'

Gem::Specification.new do |gem|
  gem.name          = "captivus-auth_hmac"
  gem.version       = Captivus::AuthHMAC::VERSION
  gem.authors       = ["Austin Schneider"]
  gem.email         = ["austinthecoder@gmail.com"]
  gem.description   = "HMAC based authentication for HTTP"
  gem.summary       = "HMAC based authentication for HTTP"
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]
end
