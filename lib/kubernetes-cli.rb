# typed: strict

require 'json'
require 'kubectl-rb'
require 'open3'
require 'shellwords'
require 'stringio'

class KubernetesCLI
  extend T::Sig

  class KubernetesError < StandardError; end

  class InvalidResourceError < KubernetesError
    extend T::Sig

    T::Sig::WithoutRuntime.sig { returns(T.nilable(::KubeDSL::DSLObject)) }
    attr_reader :resource

    T::Sig::WithoutRuntime.sig { params(resource: ::KubeDSL::DSLObject).returns(::KubeDSL::DSLObject) }
    attr_writer :resource

    T::Sig::WithoutRuntime.sig { params(args: T.untyped).void }
    def initialize(*args)
      @resource = T.let(@resource, T.nilable(::KubeDSL::DSLObject))
      super
    end
  end

  class InvalidResourceUriError < KubernetesError
    extend T::Sig

    T::Sig::WithoutRuntime.sig { returns(T.nilable(String)) }
    attr_reader :resource_uri

    T::Sig::WithoutRuntime.sig { params(resource_uri: String).returns(String) }
    attr_writer :resource_uri

    T::Sig::WithoutRuntime.sig { params(args: T.untyped).void }
    def initialize(*args)
      @resource_uri = T.let(@resource_uri, T.nilable(String))
      super
    end
  end

  class GetResourceError < KubernetesError; end
  class DeleteResourceError < KubernetesError; end
  class PatchResourceError < KubernetesError; end
  class AnnotateResourceError < KubernetesError; end
  class GetVersionError < KubernetesError; end

  STATUS_KEY = :kubernetes_cli_last_status
  STDOUT_KEY = :kubernetes_cli_stdout
  STDERR_KEY = :kubernetes_cli_stderr

  T::Sig::WithoutRuntime.sig { returns(String) }
  attr_reader :kubeconfig_path

  T::Sig::WithoutRuntime.sig { returns(String) }
  attr_reader :executable

  BeforeCallback = T.type_alias { T.proc.params(cmd: T::Array[String]).void }
  AfterCallback = T.type_alias do
    T.proc.params(cmd: T::Array[String], last_status: Process::Status).void
  end

  T::Sig::WithoutRuntime.sig { params(kubeconfig_path: String, executable: String).void }
  def initialize(kubeconfig_path, executable = KubectlRb.executable)
    @kubeconfig_path = kubeconfig_path
    @executable = executable
    @before_execute = T.let([], T::Array[BeforeCallback])
    @after_execute = T.let([], T::Array[AfterCallback])
    @env = T.let(@env, T.nilable(T::Hash[String, String]))
  end

  T::Sig::WithoutRuntime.sig { params(block: BeforeCallback).void }
  def before_execute(&block)
    @before_execute << block
  end

  T::Sig::WithoutRuntime.sig { params(block: AfterCallback).void }
  def after_execute(&block)
    @after_execute << block
  end

  T::Sig::WithoutRuntime.sig { returns(T.nilable(Process::Status)) }
  def last_status
    Thread.current[STATUS_KEY]
  end

  T::Sig::WithoutRuntime.sig { params(block: T.proc.params(last_status: Process::Status).void).void }
  def with_last_status(&block)
    block.call(T.must(last_status))
  end

  T::Sig::WithoutRuntime.sig { params(block: T.proc.params(last_status: Process::Status).void).void }
  def on_last_status_failure(&block)
    with_last_status do |ls|
      block.call(ls) unless ls.success?
    end
  end

  T::Sig::WithoutRuntime.sig { returns(T::Hash[T.untyped, T.untyped]) }
  def version
    cmd = [executable, '--kubeconfig', kubeconfig_path, 'version', '-o', 'json']
    result = backticks(cmd)

    on_last_status_failure do |last_status|
      raise GetVersionError, "couldn't get version info: "\
        "kubectl exited with status code #{last_status.exitstatus}"
    end

    begin
      JSON.parse(result)
    rescue JSON::ParserError
      raise GetVersionError, "json parsing error"
    end
  end

  T::Sig::WithoutRuntime.sig { params(cmd: T.any(String, T::Array[String])).void }
  def run_cmd(cmd)
    cmd = [executable, '--kubeconfig', kubeconfig_path, *Array(cmd)]
    execc(cmd)
  end

  T::Sig::WithoutRuntime.sig {
    params(
      container_cmd: T.any(String, T::Array[String]),
      namespace: String,
      pod: String,
      tty: T::Boolean,
      container: T.nilable(String),
      out_file: T.nilable(String)
    ).void
  }
  def exec_cmd(container_cmd, namespace, pod, tty = true, container = nil, out_file = nil)
    cmd = [executable, '--kubeconfig', kubeconfig_path, '-n', namespace, 'exec']
    cmd += ['-it'] if tty
    cmd += ['-c', container] if container
    cmd += [pod, '--', *Array(container_cmd)]
    cmd += ['>', out_file] if out_file
    execc(cmd)
  end

  T::Sig::WithoutRuntime.sig {
    params(
      container_cmd: T.any(String, T::Array[String]),
      namespace: String,
      pod: String,
      tty: T::Boolean,
      container: T.nilable(String)
    ).void
  }
  def system_cmd(container_cmd, namespace, pod, tty = true, container = nil)
    cmd = [executable, '--kubeconfig', kubeconfig_path, '-n', namespace, 'exec']
    cmd += ['-it'] if tty
    cmd += ['-c', container] if container
    cmd += [pod, '--', *Array(container_cmd)]
    systemm(cmd)
  end

  T::Sig::WithoutRuntime.sig { params(res: ::KubeDSL::DSLObject, dry_run: T::Boolean).void }
  def apply(res, dry_run: false)
    cmd = [executable, '--kubeconfig', kubeconfig_path, 'apply', '--validate']
    cmd << '--dry-run=client' if dry_run
    cmd += ['-f', '-']

    open3_w(env, cmd) do |stdin|
      stdin.puts(res.to_resource.to_yaml)
    end

    on_last_status_failure do |last_status|
      err = InvalidResourceError.new("Could not apply #{res.kind_sym} "\
        "'#{res.metadata.name}': kubectl exited with status code #{last_status.exitstatus}"
      )

      err.resource = res
      raise err
    end
  end

  T::Sig::WithoutRuntime.sig { params(uri: String, dry_run: T::Boolean).void }
  def apply_uri(uri, dry_run: false)
    cmd = [executable, '--kubeconfig', kubeconfig_path, 'apply', '--validate']
    cmd << '--dry-run=client' if dry_run
    cmd += ['-f', uri]
    systemm(cmd)

    on_last_status_failure do |last_status|
      err = InvalidResourceUriError.new("Could not apply #{uri}: "\
        "kubectl exited with status code #{last_status.exitstatus}"
      )

      err.resource_uri = uri
      raise err
    end
  end

  T::Sig::WithoutRuntime.sig {
    params(
      type: String,
      namespace: String,
      name: String
    ).returns(
      T::Hash[String, T.untyped]
    )
  }
  def get_object(type, namespace, name)
    cmd = [executable, '--kubeconfig', kubeconfig_path]
    cmd += ['-n', namespace] if namespace
    cmd += ['get', type, name]
    cmd += ['-o', 'json']

    result = backticks(cmd)

    on_last_status_failure do |last_status|
      raise GetResourceError, "couldn't get resource of type '#{type}' named '#{name}' "\
        "in namespace #{namespace}: kubectl exited with status code #{last_status.exitstatus}"
    end

    begin
      JSON.parse(result)
    rescue JSON::ParserError
      raise GetResourceError, "json parsing error"
    end
  end

  T::Sig::WithoutRuntime.sig {
    params(
      type: String,
      namespace: T.any(String, Symbol),
      match_labels: T::Hash[String, String]
    ).returns(
      T::Array[T.untyped]
    )
  }
  def get_objects(type, namespace, match_labels = {})
    cmd = [executable, '--kubeconfig', kubeconfig_path, 'get', type]

    if namespace == :all
      cmd << '--all-namespaces'
    elsif namespace
      cmd += ['-n', namespace.to_s]
    end

    unless match_labels.empty?
      cmd += ['--selector', match_labels.map { |key, value| "#{key}=#{value}" }.join(',')]
    end

    cmd += ['-o', 'json']

    result = backticks(cmd)

    on_last_status_failure do |last_status|
      raise GetResourceError, "couldn't get resources of type '#{type}' "\
        "in namespace #{namespace}: kubectl exited with status code #{last_status.exitstatus}"
    end

    begin
      JSON.parse(result)['items']
    rescue JSON::ParserError
      raise GetResourceError, "json parsing error"
    end
  end

  T::Sig::WithoutRuntime.sig {
    params(
      type: String,
      namespace: String,
      name: String
    ).void
  }
  def delete_object(type, namespace, name)
    cmd = [executable, '--kubeconfig', kubeconfig_path]
    cmd += ['-n', namespace] if namespace
    cmd += ['delete', type, name]

    systemm(cmd)

    on_last_status_failure do |last_status|
      raise DeleteResourceError, "couldn't delete resource of type '#{type}' named '#{name}' "\
        "in namespace #{namespace}: kubectl exited with status code #{last_status.exitstatus}"
    end
  end

  T::Sig::WithoutRuntime.sig {
    params(
      type: String,
      namespace: T.any(String, Symbol),
      match_labels: T::Hash[String, String]
    ).void
  }
  def delete_objects(type, namespace, match_labels = {})
    cmd = [executable, '--kubeconfig', kubeconfig_path]

    if namespace == :all
      cmd << '--all-namespaces'
    elsif namespace
      cmd += ['-n', namespace.to_s]
    end

    cmd += ['delete', type]

    unless match_labels.empty?
      cmd += ['--selector', match_labels.map { |key, value| "#{key}=#{value}" }.join(',')]
    end

    systemm(cmd)

    on_last_status_failure do |last_status|
      raise DeleteResourceError, "couldn't delete resources of type '#{type}' "\
        "in namespace #{namespace}: kubectl exited with status code #{last_status.exitstatus}"
    end
  end

  T::Sig::WithoutRuntime.sig {
    params(
      type: String,
      namespace: String,
      name: String,
      patch_data: String,
      patch_type: String
    ).void
  }
  def patch_object(type, namespace, name, patch_data, patch_type = 'merge')
    cmd = [executable, '--kubeconfig', kubeconfig_path]
    cmd += ['-n', namespace] if namespace
    cmd += ['patch', type, name]
    cmd += ['-p', Shellwords.shellescape(patch_data)]
    cmd += ['--type', patch_type]

    systemm(cmd)

    on_last_status_failure do |last_status|
      raise PatchResourceError, "couldn't patch resource of type '#{type}' named '#{name}' "\
        "in namespace #{namespace}: kubectl exited with status code #{last_status.exitstatus}"
    end
  end

  T::Sig::WithoutRuntime.sig {
    params(
      type: String,
      namespace: String,
      name: String,
      annotations: T::Hash[String, String],
      overwrite: T::Boolean
    ).void
  }
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

    on_last_status_failure do |last_status|
      raise AnnotateResourceError, "could not annotate resource '#{name}': kubectl "\
        "exited with status code #{last_status.exitstatus}"
    end
  end

  T::Sig::WithoutRuntime.sig {
    params(
      namespace: String,
      selector: T::Hash[String, String],
      follow: T::Boolean
    ).void
  }
  def logtail(namespace, selector, follow: true)
    cmd = [executable, '--kubeconfig', kubeconfig_path, '-n', namespace, 'logs']
    cmd << '-f' if follow
    cmd << '--selector'
    cmd << selector.map { |k, v| "#{k}=#{v}" }.join(',')
    execc(cmd)
  end

  T::Sig::WithoutRuntime.sig { returns(String) }
  def current_context
    cmd = [executable, '--kubeconfig', kubeconfig_path, 'config', 'current-context']
    backticks(cmd).strip
  end

  T::Sig::WithoutRuntime.sig { returns(String) }
  def api_resources
    cmd = [executable, '--kubeconfig', kubeconfig_path, 'api-resources']
    result = backticks(cmd)

    on_last_status_failure do |last_status|
      raise KubernetesError, 'could not fetch API resources: kubectl exited with '\
        "status code #{last_status.exitstatus}. #{result}"
    end

    result
  end

  T::Sig::WithoutRuntime.sig { params(namespace: String, deployment: String).void }
  def restart_deployment(namespace, deployment)
    cmd = [
      executable,
      '--kubeconfig', kubeconfig_path,
      '-n', namespace,
      'rollout', 'restart', 'deployment', deployment
    ]

    systemm(cmd)

    on_last_status_failure do |last_status|
      raise KubernetesError, 'could not restart deployment: kubectl exited with '\
        "status code #{last_status.exitstatus}"
    end
  end

  T::Sig::WithoutRuntime.sig { params(out: T.any(StringIO, IO), err: T.any(StringIO, IO), block: T.proc.void).void }
  def with_pipes(out = STDOUT, err = STDERR, &block)
    previous_stdout = self.stdout
    previous_stderr = self.stderr
    self.stdout = out
    self.stderr = err
    yield
  ensure
    self.stdout = previous_stdout
    self.stderr = previous_stderr
  end

  T::Sig::WithoutRuntime.sig { returns(T.any(StringIO, IO)) }
  def stdout
    Thread.current[STDOUT_KEY] || STDOUT
  end

  T::Sig::WithoutRuntime.sig { params(new_stdout: T.nilable(T.any(StringIO, IO))).void }
  def stdout=(new_stdout)
    Thread.current[STDOUT_KEY] = new_stdout
  end

  T::Sig::WithoutRuntime.sig { returns(T.any(StringIO, IO)) }
  def stderr
    Thread.current[STDERR_KEY] || STDERR
  end

  T::Sig::WithoutRuntime.sig { params(new_stderr: T.nilable(T.any(StringIO, IO))).void }
  def stderr=(new_stderr)
    Thread.current[STDERR_KEY] = new_stderr
  end

  T::Sig::WithoutRuntime.sig { returns(T::Hash[String, String]) }
  def env
    @env ||= {}
  end

  private

  T::Sig::WithoutRuntime.sig { returns(T::Array[String]) }
  def base_cmd
    [executable, '--kubeconfig', kubeconfig_path]
  end

  T::Sig::WithoutRuntime.sig { params(cmd: T::Array[String]).void }
  def execc(cmd)
    run_before_callbacks(cmd)
    cmd_s = cmd.join(' ')
    exec(T.unsafe(env), cmd_s)
  end

  T::Sig::WithoutRuntime.sig { params(cmd: T::Array[String]).void }
  def systemm(cmd)
    if stdout == STDOUT && stderr == STDERR
      systemm_default(cmd)
    else
      systemm_open3(cmd)
    end
  end

  T::Sig::WithoutRuntime.sig { params(cmd: T::Array[String]).void }
  def systemm_default(cmd)
    run_before_callbacks(cmd)
    cmd_s = cmd.join(' ')
    system(T.unsafe(env), cmd_s).tap do
      self.last_status = $?
      run_after_callbacks(cmd)
    end
  end

  T::Sig::WithoutRuntime.sig { params(cmd: T::Array[String]).void }
  def systemm_open3(cmd)
    run_before_callbacks(cmd)
    cmd_s = cmd.join(' ')

    Open3.popen3(T.unsafe(env), cmd_s) do |p_stdin, p_stdout, p_stderr, wait_thread|
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
      self.last_status = T.cast(wait_thread.value, Process::Status)
      run_after_callbacks(cmd)
      wait_thread.join
    end
  end

  T::Sig::WithoutRuntime.sig { params(cmd: T::Array[String]).returns(String) }
  def backticks(cmd)
    backticks_open3(cmd)
  end

  T::Sig::WithoutRuntime.sig { params(cmd: T::Array[String]).returns(String) }
  def backticks_open3(cmd)
    run_before_callbacks(cmd)
    cmd_s = cmd.join(' ')
    result = StringIO.new

    Open3.popen3(T.unsafe(env), cmd_s) do |p_stdin, p_stdout, p_stderr, wait_thread|
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
      self.last_status = T.cast(wait_thread.value, Process::Status)
      run_after_callbacks(cmd)
      wait_thread.join
    end

    result.string
  end

  T::Sig::WithoutRuntime.sig {
    params(
      env: T::Hash[String, String],
      cmd: T::Array[String],
      opts: T::Hash[Symbol, T.untyped],
      block: T.proc.params(p_stdin: IO).void
    ).void
  }
  def open3_w(env, cmd, opts = {}, &block)
    run_before_callbacks(cmd)
    cmd_s = cmd.join(' ')

    # unsafes here b/c popen3 takes an optional first argument hash
    # with environment variables, which confuses the sh*t out of sorbet
    Open3.popen3(T.unsafe(env), cmd_s, T.unsafe(opts)) do |p_stdin, p_stdout, p_stderr, wait_thread|
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

      yield(p_stdin)

      p_stdin.close
      self.last_status = T.cast(wait_thread.value, Process::Status)
      run_after_callbacks(cmd)
      wait_thread.join
    end
  end

  T::Sig::WithoutRuntime.sig { params(cmd: T::Array[String]).void }
  def run_before_callbacks(cmd)
    @before_execute.each { |cb| cb.call(cmd) }
  end

  T::Sig::WithoutRuntime.sig { params(cmd: T::Array[String]).void }
  def run_after_callbacks(cmd)
    @after_execute.each { |cb| cb.call(cmd, T.must(last_status)) }
  end

  T::Sig::WithoutRuntime.sig { params(status: Process::Status).void }
  def last_status=(status)
    Thread.current[STATUS_KEY] = status
  end
end
