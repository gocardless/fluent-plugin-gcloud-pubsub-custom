# frozen_string_literal: true

$LOAD_PATH.push File.expand_path("lib", __dir__)

Gem::Specification.new do |gem|
  gem.name        = "fluent-plugin-gcloud-pubsub-custom"
  gem.description = "Google Cloud Pub/Sub input/output plugin for Fluentd event collector"
  gem.license     = "MIT"
  gem.homepage    = "https://github.com/mia-0032/fluent-plugin-gcloud-pubsub-custom"
  gem.summary     = gem.description
  gem.version     = "1.3.2"
  gem.authors     = ["Yoshihiro MIYAI"]
  gem.email       = "msparrow17@gmail.com"
  gem.files       = `git ls-files`.split("\n")
  gem.test_files  = `git ls-files -- {test,spec,features}/*`.split("\n")
  gem.executables = `git ls-files -- bin/*`.split("\n").map { |f| File.basename(f) }
  gem.require_paths = ["lib"]

  gem.add_runtime_dependency "fluentd", [">= 0.14.15", "< 2"]
  gem.add_runtime_dependency "google-cloud-pubsub", "~> 2.19.0"

  # Use the same version constraint as fluent-plugin-prometheus currently specifies
  gem.add_runtime_dependency "prometheus-client", ">= 2.1.0"

  gem.add_development_dependency "bundler"
  gem.add_development_dependency "pry"
  gem.add_development_dependency "pry-byebug"
  gem.add_development_dependency "rake"
  gem.add_development_dependency "rubocop"
  gem.add_development_dependency "test-unit"
  gem.add_development_dependency "test-unit-rr"
end
