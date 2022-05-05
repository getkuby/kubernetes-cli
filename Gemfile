source 'https://rubygems.org'

gemspec

# Declare platform-specific gems here so they install correctly.
# See: https://github.com/rubygems/rubygems/issues/3646
gem 'kubectl-rb'

group :test do
  gem 'rspec'
  gem 'kind-rb', '~> 0.1'
  gem 'kube-dsl', '~> 0.6'
end

group :development do
  gem 'curdle', '~> 1.0'

  # lock to same version as kuby-core
  gem 'sorbet', '= 0.5.6433'
  gem 'parlour', '~> 6.0'
end

group :development, :test do
  gem 'pry-byebug'
  gem 'rake'
end
