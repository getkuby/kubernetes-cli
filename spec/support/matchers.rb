# typed: false
require 'rspec/expectations'

class TestCommand
  def initialize(env, cmd_s)
    @env = env
    @cmd_s = cmd_s
    @cmd = cmd_s.split(' ')
  end

  def includes?(args)
    @cmd.each_cons(args.size).any? do |sub_cmd|
      sub_cmd == args
    end
  end

  def excludes?(args)
    @cmd.each_cons(args.size).all? do |sub_cmd|
      sub_cmd != args
    end
  end

  def redirects_to?(path)
    @cmd[-2..-1] == ['>', path]
  end
end

module CommandHelpers
  def self.handle_commands(commands)
    @with_args ||= []
    @without_args ||= []
    @missing = []
    @extra = []
    @missing_redirect = false

    commands.map! { |env, cmd_s| TestCommand.new(env, cmd_s) }

    @matching_commands = commands.select do |cmd|
      missing_for_cmd = []

      @with_args.each do |with_args|
        missing_for_cmd << with_args unless cmd.includes?(with_args)
      end

      @missing << missing_for_cmd unless missing_for_cmd.empty?
      missing_for_cmd.empty?
    end

    @matching_commands.select! do |cmd|
      extra_for_cmd = []

      @without_args.each do |without_args|
        extra_for_cmd << without_args unless cmd.excludes?(without_args)
      end

      @extra << extra_for_cmd unless extra_for_cmd.empty?
      extra_for_cmd.empty?
    end

    if @redirect_path
      @matching_commands.select! do |cmd|
        cmd.redirects_to?(@redirect_path).tap do |does_redirect|
          @missing_redirect = true unless does_redirect
        end
      end
    end

    !@matching_commands.empty?
  end

  def self.failure_message
    message_parts = [].tap do |message_parts|
      if @matching_commands.empty?
        return 'No commands were executed.'
      end

      unless @missing.empty?
        missing_for_all = @missing[0].intersection(*@missing)
        missing_str = missing_for_all.map { |m| "  #{m.join(' ')}" }.join("\n")
        message_parts << "expected at least one command to contain args:\n#{missing_str}"
      end

      unless @extra.empty?
        extra_for_any = @extra[0].union(*@extra)
        extra_str = extra_for_any.map { |m| "  #{m.join(' ')}" }.join("\n")
        message_parts << "at least one viable command contained unexpected args:\n#{extra_str}"
      end

      if @missing_redirect
        message_parts << "at least one viable command did not redirect to #{@redirect_path}"
      end
    end

    message_parts.join("\n\n")
  end
end

RSpec::Matchers.define :run_exec do |_expected|
  match do |actual|
    instance_eval do
      CommandHelpers.handle_commands(actual.exec_commands)
    end
  end

  # args should be an array of arrays
  chain :with_args do |*with_args|
    @with_args = with_args
  end

  chain :without_args do |*without_args|
    @without_args = without_args
  end

  chain :and_redirect_to do |path|
    @redirect_path = path
  end

  failure_message do
    instance_eval do
      CommandHelpers.failure_message
    end
  end
end
