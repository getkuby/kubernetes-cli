require 'bundler'
require 'rspec/core/rake_task'
require 'rubygems/package_task'

require 'sorbet-runtime'
require 'kubernetes-cli'
require 'curdle'

Curdle::Tasks.install

task default: :spec

desc 'Run specs'
RSpec::Core::RakeTask.new do |t|
  t.pattern = './spec/**/*_spec.rb'
end
