# frozen_string_literal: true

$LOAD_PATH.push File.expand_path("lib", __dir__)

Gem::Specification.new do |gem|
  gem.name        = "fluent-plugin-gcloud-pubsub-custom-compress-batches"
  gem.description = "Google Cloud Pub/Sub input/output plugin for Fluentd event collector - with payload compression. Forked from https://github.com/gocardless/fluent-plugin-gcloud-pubsub-custom"
  gem.license     = "MIT"
  gem.homepage    = "https://github.com/calvinaditya95/fluent-plugin-gcloud-pubsub-custom"
  gem.summary     = "Google Cloud Pub/Sub input/output plugin for Fluentd event collector - with payload compression"
  gem.version     = "1.3.3"
  gem.authors     = ["Calvin Aditya"]
  gem.email       = "calvin.aditya95@gmail.com"
  gem.files       = `git ls-files`.split("\n")
  gem.test_files  = `git ls-files -- {test,spec,features}/*`.split("\n")
  gem.executables = `git ls-files -- bin/*`.split("\n").map { |f| File.basename(f) }
  gem.require_paths = ["lib"]

  gem.add_runtime_dependency "fluentd", [">= 0.14.15", "< 2"]
  gem.add_runtime_dependency "google-cloud-pubsub", "~> 0.30.0"

  # Use the same version constraint as fluent-plugin-prometheus currently specifies
  gem.add_runtime_dependency "prometheus-client", "< 0.10"

  gem.add_development_dependency "bundler"
  gem.add_development_dependency "pry"
  gem.add_development_dependency "pry-byebug"
  gem.add_development_dependency "rake"
  gem.add_development_dependency "rubocop", "~>0.83"
  gem.add_development_dependency "test-unit"
  gem.add_development_dependency "test-unit-rr"
end
