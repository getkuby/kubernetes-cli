# typed: strong
class KubernetesCLI
  extend T::Sig
  BeforeCallback = T.type_alias { T.proc.params(cmd: T::Array[String]).void }
  AfterCallback = T.type_alias { T.proc.params(cmd: T::Array[String], last_status: Process::Status).void }
  STATUS_KEY = :kubernetes_cli_last_status
  STDOUT_KEY = :kubernetes_cli_stdout
  STDERR_KEY = :kubernetes_cli_stderr

  class KubernetesError < StandardError
  end

  class InvalidResourceError < KubernetesError
    extend T::Sig

    sig { returns(T.nilable(::KubeDSL::DSLObject)) }
    attr_reader :resource

    sig { params(resource: ::KubeDSL::DSLObject).returns(::KubeDSL::DSLObject) }
    attr_writer :resource

    sig { params(args: T.untyped).void }
    def initialize(*args); end
  end

  class InvalidResourceUriError < KubernetesError
    extend T::Sig

    sig { returns(T.nilable(String)) }
    attr_reader :resource_uri

    sig { params(resource_uri: String).returns(String) }
    attr_writer :resource_uri

    sig { params(args: T.untyped).void }
    def initialize(*args); end
  end

  class GetResourceError < KubernetesError
  end

  class DeleteResourceError < KubernetesError
  end

  class PatchResourceError < KubernetesError
  end

  class AnnotateResourceError < KubernetesError
  end

  class GetVersionError < KubernetesError
  end

  sig { returns(String) }
  attr_reader :kubeconfig_path

  sig { returns(String) }
  attr_reader :executable

  sig { params(kubeconfig_path: String, executable: String).void }
  def initialize(kubeconfig_path, executable = KubectlRb.executable); end

  sig { params(block: BeforeCallback).void }
  def before_execute(&block); end

  sig { params(block: AfterCallback).void }
  def after_execute(&block); end

  sig { returns(T.nilable(Process::Status)) }
  def last_status; end

  sig { params(block: T.proc.params(last_status: Process::Status).void).void }
  def with_last_status(&block); end

  sig { params(block: T.proc.params(last_status: Process::Status).void).void }
  def on_last_status_failure(&block); end

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def version; end

  sig { params(cmd: T.any(String, T::Array[String])).void }
  def run_cmd(cmd); end

  sig do
    params(
      container_cmd: T.any(String, T::Array[String]),
      namespace: String,
      pod: String,
      tty: T::Boolean,
      container: T.nilable(String),
      out_file: T.nilable(String)
    ).void
  end
  def exec_cmd(container_cmd, namespace, pod, tty = true, container = nil, out_file = nil); end

  sig do
    params(
      container_cmd: T.any(String, T::Array[String]),
      namespace: String,
      pod: String,
      tty: T::Boolean,
      container: T.nilable(String)
    ).void
  end
  def system_cmd(container_cmd, namespace, pod, tty = true, container = nil); end

  sig { params(res: ::KubeDSL::DSLObject, dry_run: T::Boolean).void }
  def apply(res, dry_run: false); end

  sig { params(uri: String, dry_run: T::Boolean).void }
  def apply_uri(uri, dry_run: false); end

  sig { params(type: String, namespace: String, name: String).returns(T::Hash[String, T.untyped]) }
  def get_object(type, namespace, name); end

  sig { params(type: String, namespace: T.any(String, Symbol), match_labels: T::Hash[String, String]).returns(T::Array[T.untyped]) }
  def get_objects(type, namespace, match_labels = {}); end

  sig { params(type: String, namespace: String, name: String).void }
  def delete_object(type, namespace, name); end

  sig { params(type: String, namespace: T.any(String, Symbol), match_labels: T::Hash[String, String]).void }
  def delete_objects(type, namespace, match_labels = {}); end

  sig do
    params(
      type: String,
      namespace: String,
      name: String,
      patch_data: String,
      patch_type: String
    ).void
  end
  def patch_object(type, namespace, name, patch_data, patch_type = 'merge'); end

  sig do
    params(
      type: String,
      namespace: String,
      name: String,
      annotations: T::Hash[String, String],
      overwrite: T::Boolean
    ).void
  end
  def annotate(type, namespace, name, annotations, overwrite: true); end

  sig { params(namespace: String, selector: T::Hash[String, String], follow: T::Boolean).void }
  def logtail(namespace, selector, follow: true); end

  sig { returns(String) }
  def current_context; end

  sig { returns(String) }
  def api_resources; end

  sig { params(namespace: String, deployment: String).void }
  def restart_deployment(namespace, deployment); end

  sig { params(out: T.any(StringIO, IO), err: T.any(StringIO, IO), block: T.proc.void).void }
  def with_pipes(out = STDOUT, err = STDERR, &block); end

  sig { returns(T.any(StringIO, IO)) }
  def stdout; end

  sig { params(new_stdout: T.nilable(T.any(StringIO, IO))).void }
  def stdout=(new_stdout); end

  sig { returns(T.any(StringIO, IO)) }
  def stderr; end

  sig { params(new_stderr: T.nilable(T.any(StringIO, IO))).void }
  def stderr=(new_stderr); end

  sig { returns(T::Hash[String, String]) }
  def env; end

  sig { returns(T::Array[String]) }
  def base_cmd; end

  sig { params(cmd: T::Array[String]).void }
  def execc(cmd); end

  sig { params(cmd: T::Array[String]).void }
  def systemm(cmd); end

  sig { params(cmd: T::Array[String]).void }
  def systemm_default(cmd); end

  sig { params(cmd: T::Array[String]).void }
  def systemm_open3(cmd); end

  sig { params(cmd: T::Array[String]).returns(String) }
  def backticks(cmd); end

  sig { params(cmd: T::Array[String]).returns(String) }
  def backticks_open3(cmd); end

  sig do
    params(
      env: T::Hash[String, String],
      cmd: T::Array[String],
      opts: T::Hash[Symbol, T.untyped],
      block: T.proc.params(p_stdin: IO).void
    ).void
  end
  def open3_w(env, cmd, opts = {}, &block); end

  sig { params(cmd: T::Array[String]).void }
  def run_before_callbacks(cmd); end

  sig { params(cmd: T::Array[String]).void }
  def run_after_callbacks(cmd); end

  sig { params(status: Process::Status).void }
  def last_status=(status); end
end
