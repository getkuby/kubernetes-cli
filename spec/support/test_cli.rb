# typed: ignore

require 'kubectl-rb'
require 'kubernetes-cli'
require 'stringio'

class FakeStatus
  attr_reader :exitstatus

  def initialize(exitstatus)
    @exitstatus = exitstatus
  end

  def success?
    exitstatus == 0
  end
end

class TestCLI < KubernetesCLI
  attr_reader :exec_commands

  def initialize(kubeconfig_path, executable = KubectlRb.executable)
    @exec_commands = []

    super
  end

  def exec(env, cmd)
    @exec_commands << [env, cmd]
  end
end
