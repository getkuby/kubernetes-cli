require 'kubectl-rb'
require 'open3'
require 'stringio'

class KubernetesCLI
  class KubernetesError < StandardError; end

  class InvalidResourceError < KubernetesError
    attr_accessor :resource
  end

  class InvalidResourceUriError < KubernetesError
    attr_accessor :resource_uri
  end

  class GetResourceError < KubernetesError; end

  STATUS_KEY = :kubernetes_cli_last_status
  STDOUT_KEY = :kubernetes_cli_stdout
  STDERR_KEY = :kubernetes_cli_stderr

  attr_reader :kubeconfig_path, :executable

  def initialize(kubeconfig_path, executable = KubectlRb.executable)
    @kubeconfig_path = kubeconfig_path
    @executable = executable
    @before_execute = []
    @after_execute = []
  end

  def before_execute(&block)
    @before_execute << block
  end

  def after_execute(&block)
    @after_execute << block
  end

  def last_status
    Thread.current[STATUS_KEY]
  end

  def run_cmd(cmd)
    cmd = [executable, '--kubeconfig', kubeconfig_path, *Array(cmd)]
    execc(cmd)
  end

  def exec_cmd(container_cmd, namespace, pod, tty = true)
    cmd = [executable, '--kubeconfig', kubeconfig_path, '-n', namespace, 'exec']
    cmd += ['-it'] if tty
    cmd += [pod, '--', *Array(container_cmd)]
    execc(cmd)
  end

  def system_cmd(container_cmd, namespace, pod, tty = true)
    cmd = [executable, '--kubeconfig', kubeconfig_path, '-n', namespace, 'exec']
    cmd += ['-it'] if tty
    cmd += [pod, '--', *Array(container_cmd)]
    systemm(cmd)
  end

  def apply(res, dry_run: false)
    cmd = [executable, '--kubeconfig', kubeconfig_path, 'apply', '--validate']
    cmd << '--dry-run=client' if dry_run
    cmd += ['-f', '-']

    open3_w(env, cmd) do |stdin|
      stdin.puts(res.to_resource.to_yaml)
    end

    unless last_status.success?
      err = InvalidResourceError.new("Could not apply #{res.kind_sym.to_s.humanize.downcase} "\
        "'#{res.metadata.name}': kubectl exited with status code #{last_status.exitstatus}"
      )

      err.resource = res
      raise err
    end
  end

  def apply_uri(uri, dry_run: false)
    cmd = [executable, '--kubeconfig', kubeconfig_path, 'apply', '--validate']
    cmd << '--dry-run=client' if dry_run
    cmd += ['-f', uri]
    systemm(cmd)

    unless last_status.success?
      err = InvalidResourceUriError.new("Could not apply #{uri}: "\
        "kubectl exited with status code #{last_status.exitstatus}"
      )

      err.resource_uri = uri
      raise err
    end
  end

  def get_object(type, namespace, name = nil, match_labels = {})
    cmd = [executable, '--kubeconfig', kubeconfig_path, '-n', namespace]
    cmd += ['get', type, name]

    unless match_labels.empty?
      cmd += ['--selector', match_labels.map { |key, value| "#{key}=#{value}" }.join(',')]
    end

    cmd += ['-o', 'json']

    result = backticks(cmd)

    unless last_status.success?
      raise GetResourceError, "couldn't get resources of type '#{type}' "\
        "in namespace #{namespace}: kubectl exited with status code #{last_status.exitstatus}"
    end

    JSON.parse(result)
  end

  def get_objects(type, namespace, match_labels = {})
    cmd = [executable, '--kubeconfig', kubeconfig_path, '-n', namespace]
    cmd += ['get', type]

    unless match_labels.empty?
      cmd += ['--selector', match_labels.map { |key, value| "#{key}=#{value}" }.join(',')]
    end

    cmd += ['-o', 'json']

    result = backticks(cmd)

    unless last_status.success?
      raise GetResourceError, "couldn't get resources of type '#{type}' "\
        "in namespace #{namespace}: kubectl exited with status code #{last_status.exitstatus}"
    end

    JSON.parse(result)['items']
  end

  def annotate(type, namespace, name, annotations, overwrite: true)
    cmd = [
      executable,
      '--kubeconfig', kubeconfig_path,
      '-n', namespace,
      'annotate'
    ]

    cmd << '--overwrite' if overwrite
    cmd += [type, name]

    annotations.each do |key, value|
      cmd << "'#{key}'='#{value}'"
    end

    systemm(cmd)

    unless last_status.success?
      raise KubernetesError, "could not annotate resource '#{name}': kubectl "\
        "exited with status code #{last_status.exitstatus}"
    end
  end

  def logtail(namespace, selector, follow: true)
    cmd = [executable, '--kubeconfig', kubeconfig_path, '-n', namespace, 'logs']
    cmd << '-f' if follow
    cmd << '--selector'
    cmd << selector.map { |k, v| "#{k}=#{v}" }.join(',')
    execc(cmd)
  end

  def current_context
    cmd = [executable, '--kubeconfig', kubeconfig_path, 'config', 'current-context']
    backticks(cmd).strip
  end

  def api_resources
    cmd = [executable, '--kubeconfig', kubeconfig_path, 'api-resources']
    result = backticks(cmd)

    unless last_status.success?
      raise KubernetesError, 'could not fetch API resources: kubectl exited with '\
        "status code #{last_status.exitstatus}. #{result}"
    end

    result
  end

  def restart_deployment(namespace, deployment)
    cmd = [
      executable,
      '--kubeconfig', kubeconfig_path,
      '-n', namespace,
      'rollout', 'restart', 'deployment', deployment
    ]

    systemm(cmd)

    unless last_status.success?
      raise KubernetesError, 'could not restart deployment: kubectl exited with '\
        "status code #{last_status.exitstatus}"
    end
  end

  def with_pipes(out = STDOUT, err = STDERR)
    previous_stdout = self.stdout
    previous_stderr = self.stderr
    self.stdout = out
    self.stderr = err
    yield
  ensure
    self.stdout = previous_stdout
    self.stderr = previous_stderr
  end

  def stdout
    Thread.current[STDOUT_KEY] || STDOUT
  end

  def stdout=(new_stdout)
    Thread.current[STDOUT_KEY] = new_stdout
  end

  def stderr
    Thread.current[STDERR_KEY] || STDERR
  end

  def stderr=(new_stderr)
    Thread.current[STDERR_KEY] = new_stderr
  end

  private

  def env
    @env ||= {}
  end

  def base_cmd
    [executable, '--kubeconfig', kubeconfig_path]
  end

  def execc(cmd)
    run_before_callbacks(cmd)
    cmd_s = cmd.join(' ')
    exec(cmd_s)
  end

  def systemm(cmd)
    if stdout == STDOUT && stderr == STDERR
      systemm_default(cmd)
    else
      systemm_open3(cmd)
    end
  end

  def systemm_default(cmd)
    run_before_callbacks(cmd)
    cmd_s = cmd.join(' ')
    system(cmd_s).tap do
      self.last_status = $?
      run_after_callbacks(cmd)
    end
  end

  def systemm_open3(cmd)
    run_before_callbacks(cmd)
    cmd_s = cmd.join(' ')

    Open3.popen3(cmd_s) do |p_stdin, p_stdout, p_stderr, wait_thread|
      Thread.new(stdout) do |t_stdout|
        begin
          p_stdout.each { |line| t_stdout.puts(line) }
        rescue IOError
        end
      end

      Thread.new(stderr) do |t_stderr|
        begin
          p_stderr.each { |line| t_stderr.puts(line) }
        rescue IOError
        end
      end

      p_stdin.close
      self.last_status = wait_thread.value
      run_after_callbacks(cmd)
      wait_thread.join
    end
  end

  def backticks(cmd)
    if stdout == STDOUT && stderr == STDERR
      backticks_default(cmd)
    else
      backticks_open3(cmd)
    end
  end

  def backticks_default(cmd)
    run_before_callbacks(cmd)
    cmd_s = cmd.join(' ')
    `#{cmd_s}`.tap do
      self.last_status = $?
      run_after_callbacks(cmd)
    end
  end

  def backticks_open3(cmd)
    run_before_callbacks(cmd)
    cmd_s = cmd.join(' ')
    result = StringIO.new

    Open3.popen3(cmd_s) do |p_stdin, p_stdout, p_stderr, wait_thread|
      Thread.new do
        begin
          p_stdout.each { |line| result.puts(line) }
        rescue IOError
        end
      end

      Thread.new(stderr) do |t_stderr|
        begin
          p_stderr.each { |line| t_stderr.puts(line) }
        rescue IOError
        end
      end

      p_stdin.close
      self.last_status = wait_thread.value
      run_after_callbacks(cmd)
      wait_thread.join
    end

    result.string
  end

  def open3_w(env, cmd, opts = {}, &block)
    run_before_callbacks(cmd)
    cmd_s = cmd.join(' ')

    Open3.popen3(env, cmd_s, opts) do |p_stdin, p_stdout, p_stderr, wait_thread|
      Thread.new(stdout) do |t_stdout|
        begin
          p_stdout.each { |line| t_stdout.puts(line) }
        rescue IOError
        end
      end

      Thread.new(stderr) do |t_stderr|
        begin
          p_stderr.each { |line| t_stderr.puts(line) }
        rescue IOError
        end
      end

      yield(p_stdin).tap do
        p_stdin.close
        self.last_status = wait_thread.value
        run_after_callbacks(cmd)
        wait_thread.join
      end
    end
  end

  def run_before_callbacks(cmd)
    @before_execute.each { |cb| cb.call(cmd) }
  end

  def run_after_callbacks(cmd)
    @after_execute.each { |cb| cb.call(cmd, last_status) }
  end

  def last_status=(status)
    Thread.current[STATUS_KEY] = status
  end
end
