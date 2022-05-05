$:.unshift File.join(File.dirname(__FILE__), 'lib')
require 'kubernetes-cli/version'

Gem::Specification.new do |s|
  s.name     = 'kubernetes-cli'
  s.version  = ::KubernetesCLI::VERSION
  s.authors  = ['Cameron Dutro']
  s.email    = ['camertron@gmail.com']
  s.homepage = 'http://github.com/getkuby/kubernetes-cli'
  s.license  = 'MIT'

  s.description = s.summary = 'Ruby wrapper around the Kubernetes CLI.'

  s.add_dependency 'kubectl-rb', '~> 0.2'

  s.require_path = 'lib'
  s.files = Dir['{lib,spec,rbi}/**/*', 'Gemfile', 'LICENSE', 'CHANGELOG.md', 'README.md', 'Rakefile', 'kubernetes-cli.gemspec']
end
