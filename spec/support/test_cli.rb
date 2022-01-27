# typed: true
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
  attr_reader :exec_commands, :system_commands

  def initialize(*args, **kwargs, &block)
    @exec_commands = []
    @system_commands = []

    super
  end

  def on_exec(&block)
    @exec_callback = block
  end

  def exec(cmd)
    @exec_commands << cmd
    @exec_callback.call(cmd) if @exec_callback
  end
end
