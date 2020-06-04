require 'kubectl-rb'

class KubernetesCLI
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
    Thread.current[status_key]
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

  def apply(res, dry_run: false)
    cmd = [executable, '--kubeconfig', kubeconfig_path, 'apply', '--validate']
    cmd << '--dry-run=client' if dry_run
    cmd += ['-f', '-']

    open3_w(env, cmd) do |stdin, _wait_thread|
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
      raise KubernetesCLIError, "could not annotate resource '#{name}': kubectl "\
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

  private

  def env
    @env ||= {}
  end

  def status_key
    :kubernetes_cli_last_status
  end

  def base_cmd
    [executable, '--kubeconfig', kubeconfig_path]
  end

  def backticks(cmd)
    cmd_s = cmd.join(' ')
    `#{cmd_s}`.tap do
      self.last_status = $?
    end
  end

  def execc(cmd)
    run_before_callbacks(cmd)
    cmd_s = cmd.join(' ')
    exec(cmd_s)
  end

  def systemm(cmd)
    run_before_callbacks(cmd)
    cmd_s = cmd.join(' ')
    system(cmd_s).tap do
      self.last_status = $?
      run_after_callbacks(cmd)
    end
  end

  def backticks(cmd)
    run_before_callbacks(cmd)
    cmd_s = cmd.join(' ')
    `#{cmd_s}`.tap do
      self.last_status = $?
      run_after_callbacks(cmd)
    end
  end

  def open3_w(env, cmd, opts = {}, &block)
    run_before_callbacks(cmd)
    cmd_s = cmd.join(' ')

    Open3.pipeline_w([env, cmd_s], opts) do |stdin, wait_threads|
      yield(stdin, wait_threads).tap do
        stdin.close
        self.last_status = wait_threads.last.value
        run_after_callbacks(cmd)
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
    Thread.current[status_key] = status
  end
end
