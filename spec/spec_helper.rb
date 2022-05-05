# typed: ignore

$:.push(File.expand_path('.', __dir__))

require 'sorbet-runtime'
require 'kubernetes-cli'
require 'pry-byebug'
require 'kind-rb'
require 'kube-dsl'

require 'support/matchers'
require 'support/test_cli'
require 'support/test_resource'

RSpec.configure do |config|
  config.before(:suite) do
    system("#{KindRb.executable} create cluster --name kubernetes-cli-tests")
    system("#{KubectlRb.executable} create namespace test")
  end

  config.after(:suite) do
    puts # newline to separate test output from kind output
    system("#{KindRb.executable} delete cluster --name kubernetes-cli-tests")
  end
end
