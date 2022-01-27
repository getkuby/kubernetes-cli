# typed: ignore

require 'spec_helper'
require 'stringio'

describe KubernetesCLI do
  let(:kubeconfig_path) { File.join(ENV['HOME'], '.kube', 'config') }
  let(:cli) { described_class.new(kubeconfig_path) }
  let(:fake_cli) { TestCLI.new(kubeconfig_path) }

  let(:deployment) do
    KubeDSL.deployment do
      metadata do
        name 'test-deployment'
        namespace 'test'
      end

      spec do
        replicas 1

        selector do
          match_labels do
            add :foo, 'bar'
          end
        end

        template do
          metadata do
            labels do
              add :foo, 'bar'
            end
          end

          spec do
            container(:ruby) do
              image 'ruby:3.0'
              image_pull_policy 'IfNotPresent'
              name 'ruby'
              command ['ruby', '-e', 'STDOUT.sync = true; loop { puts "alive"; sleep 5 }']
            end
          end
        end
      end
    end
  end

  around do |example|
    if ENV.fetch('SHOW_STDOUT', 'false') == 'true'
      example.run
    else
      File.open(File::NULL, 'w') do |f|
        cli.with_pipes(f, f) { example.run }
      end
    end
  end

  describe '#run_cmd' do
    it 'includes the kubeconfig' do
      fake_cli.run_cmd(%w(ls))
      expect(fake_cli).to run_exec.with_args(['--kubeconfig', kubeconfig_path])
    end

    it 'runs a kubectl command' do
      fake_cli.run_cmd(%w(ls))
      expect(fake_cli).to run_exec.with_args(['ls'])
    end
  end

  describe '#system_cmd' do
    it 'runs a command in a pod' do
      cli.apply(deployment)
      wait_for_deployment(deployment)

      pods = cli.get_objects(
        'Pod',
        deployment.metadata.namespace,
        deployment.spec.selector.match_labels.kv_pairs
      )

      stdout = StringIO.new

      cli.with_pipes(stdout) do
        cli.system_cmd(
          ['ruby', '-e', '"STDOUT.sync = true; puts 1 + 1"'],
          deployment.metadata.namespace,
          pods.first.dig(*%w(metadata name)),
          false,
          deployment.spec.template.spec.container(:ruby).name
        )
      end

      expect(stdout.string.to_i).to eq(2)
    ensure
      safely_delete_res(deployment)
    end
  end

  describe '#exec_cmd' do
    let(:container_cmd) { %w(ls) }
    let(:namespace) { 'namespace' }
    let(:pod) { 'pod' }
    let(:container) { 'container' }
    let(:out_file) { '/path/to/file' }

    it 'includes the path to the kubeconfig' do
      fake_cli.exec_cmd(container_cmd, namespace, pod)
      expect(fake_cli).to run_exec.with_args(['--kubeconfig', kubeconfig_path])
    end

    it 'includes the container command, namespace, and pod' do
      fake_cli.exec_cmd(container_cmd, namespace, pod)
      expect(fake_cli).to run_exec.with_args(['-n', namespace], [pod], ['--', 'ls'])
    end

    it 'starts a TTY by default' do
      fake_cli.exec_cmd(container_cmd, namespace, pod)
      expect(fake_cli).to run_exec.with_args(['-it'])
    end

    it 'does not start a TTY when asked not to' do
      fake_cli.exec_cmd(container_cmd, namespace, pod, false)
      expect(fake_cli).to run_exec.without_args(['-it'])
    end

    it 'selects the container when given' do
      fake_cli.exec_cmd(container_cmd, namespace, pod, true, container)
      expect(fake_cli).to run_exec.with_args(['-c', container])
    end

    it 'redirects standard output to a file when a file is given' do
      fake_cli.exec_cmd(container_cmd, namespace, pod, true, nil, out_file)
      expect(fake_cli).to run_exec.and_redirect_to(out_file)
    end
  end

  describe '#apply' do
    let(:res) do
      KubeDSL.config_map do
        metadata do
          namespace 'test'
          name 'test-config'
        end

        data do
          add 'key', 'value'
        end
      end
    end

    let(:bad_res) do
      klass = Class.new(KubeDSL::DSL::V1::ConfigMap) do
        value_field :non_existent

        def serialize
          super.merge(nonExistent: non_existent)
        end
      end

      klass.new do
        metadata do
          namespace 'test'
          name 'test-config'
        end

        non_existent 'bad'
      end
    end

    it 'applies the resource' do
      cli.apply(res)
      obj = get_object(res)
      expect(obj['data']).to eq({ 'key' => 'value' })
    ensure
      safely_delete_res(res)
    end

    it 'raises an error if the resource is malformed' do
      expect { cli.apply(bad_res) }.to raise_error do |error|
        expect(error).to be_a(KubernetesCLI::InvalidResourceError)
        expect(error.resource).to eq(bad_res)
      end
    end

    it "doesn't apply the resource if asked to perform a dry run" do
      cli.apply(res, dry_run: true)
      expect { get_object(res) }.to raise_error(KubernetesCLI::GetResourceError)
    end
  end

  describe '#apply_uri' do
    let(:url) { 'https://raw.githubusercontent.com/getkuby/kubernetes-cli/master/spec/support/test_config_map.yaml' }
    let(:bad_url) { 'https://raw.githubusercontent.com/getkuby/kubernetes-cli/master/spec/support/test_config_map_bad.yaml' }
    let(:kind) { 'ConfigMap' }
    let(:name) { 'test' }
    let(:namespace) { 'test-config-external' }

    it 'applies the external file' do
      cli.apply_uri(url)
      obj = cli.get_object(kind, name, namespace)
      expect(obj['data']).to eq({ 'key' => 'external value' })
    ensure
      begin
        cli.delete_object(kind, name, namespace)
      rescue KubernetesCLI::DeleteResourceError
      end
    end

    it 'raises an error if the resource is malformed' do
      expect { cli.apply_uri(bad_url) }.to raise_error do |error|
        expect(error).to be_a(KubernetesCLI::InvalidResourceUriError)
        expect(error.resource_uri).to eq(bad_url)
      end
    end

    it "doesn't apply the resource if asked to perform a dry run" do
      cli.apply_uri(url, dry_run: true)
      expect { cli.get_object(kind, name, namespace) }.to raise_error(KubernetesCLI::GetResourceError)
    end
  end

  describe '#get_object' do
    let(:res) do
      KubeDSL.config_map do
        metadata do
          namespace 'test'
          name 'test-config'
          labels do
            add :foo, 'bar'
          end
        end

        data do
          add 'key', 'value'
        end
      end
    end

    it 'gets the object by name' do
      cli.apply(res)
      obj = cli.get_object('ConfigMap', res.metadata.namespace, res.metadata.name)
      expect(obj['data']).to eq({ 'key' => 'value' })
    ensure
      safely_delete_res(res)
    end
  end

  describe '#get_objects' do
    let(:res1) do
      KubeDSL.config_map do
        metadata do
          namespace 'test'
          name 'test-config1'
          labels do
            add :foo, 'bar'
          end
        end

        data do
          add 'key1', 'value1'
        end
      end
    end

    let(:res2) do
      KubeDSL.config_map do
        metadata do
          namespace 'test'
          name 'test-config2'
          labels do
            add :baz, 'boo'
          end
        end

        data do
          add 'key2', 'value2'
        end
      end
    end

    let(:res3) do
      KubeDSL.config_map do
        metadata do
          namespace 'test'
          name 'test-config3'
          labels do
            add :foo, 'bar'
          end
        end

        data do
          add 'key3', 'value3'
        end
      end
    end

    it 'gets the object by its labels' do
      cli.apply(res1)
      cli.apply(res2)
      cli.apply(res3)
      obj = cli.get_objects('ConfigMap', res1.metadata.namespace, foo: 'bar')
      expect(obj.size).to eq(2)
      expect(obj.map { |o| o['metadata']['name'] }.sort).to eq(
        ['test-config1', 'test-config3']
      )
    ensure
      safely_delete_res(res1)
      safely_delete_res(res2)
      safely_delete_res(res3)
    end
  end

  describe '#delete_object' do
    let(:res) do
      KubeDSL.config_map do
        metadata do
          namespace 'test'
          name 'test-config'
        end

        data do
          add 'key', 'value'
        end
      end
    end

    it 'deletes the resource' do
      cli.apply(res)
      cli.delete_object('ConfigMap', res.metadata.namespace, res.metadata.name)
      expect { get_object(res) }.to raise_error(KubernetesCLI::GetResourceError)
    ensure
      safely_delete_res(res)
    end

    it "raises an error if the resource doesn't exist" do
      expect { cli.delete_object('ConfigMap', res.metadata.namespace, res.metadata.name) }.to(
        raise_error(KubernetesCLI::DeleteResourceError)
      )
    end
  end

  describe '#delete_objects' do
    let(:res1) do
      KubeDSL.config_map do
        metadata do
          namespace 'test'
          name 'test-config1'
          labels do
            add :foo, 'bar'
          end
        end

        data do
          add 'key1', 'value1'
        end
      end
    end

    let(:res2) do
      KubeDSL.config_map do
        metadata do
          namespace 'test'
          name 'test-config2'
          labels do
            add :baz, 'boo'
          end
        end

        data do
          add 'key2', 'value2'
        end
      end
    end

    let(:res3) do
      KubeDSL.config_map do
        metadata do
          namespace 'test'
          name 'test-config3'
          labels do
            add :foo, 'bar'
          end
        end

        data do
          add 'key3', 'value3'
        end
      end
    end

    it 'deletes objects by their labels' do
      cli.apply(res1)
      cli.apply(res2)
      cli.apply(res3)
      cli.delete_objects('ConfigMap', res1.metadata.namespace, foo: 'bar')
      expect { get_object(res1) }.to raise_error(KubernetesCLI::GetResourceError)
      expect { get_object(res3) }.to raise_error(KubernetesCLI::GetResourceError)
    ensure
      safely_delete_res(res1)
      safely_delete_res(res2)
      safely_delete_res(res3)
    end
  end

  describe '#patch_object' do
    let(:res) do
      KubeDSL.config_map do
        metadata do
          namespace 'test'
          name 'test-config'
        end

        data do
          add 'key', 'value'
        end
      end
    end

    it 'patches the object' do
      cli.apply(res)
      cli.patch_object('ConfigMap', res.metadata.namespace, res.metadata.name, '{"data":{"key":"patched"}}')
      obj = get_object(res)
      expect(obj['data']).to eq({ "key" => "patched" })
    ensure
      safely_delete_res(res)
    end

    it 'raises an error when patching fails' do
      cli.apply(res)
      expect {
        cli.patch_object('ConfigMap', res.metadata.namespace, res.metadata.name, '{"data":{"key":}}')
      }.to raise_error(KubernetesCLI::PatchResourceError)
    ensure
      safely_delete_res(res)
    end
  end

  describe '#annotate' do
    let(:res) do
      KubeDSL.config_map do
        metadata do
          namespace 'test'
          name 'test-config'
        end

        data do
          add 'key', 'value'
        end
      end
    end

    it 'annotates the resource' do
      cli.apply(res)
      cli.annotate('ConfigMap', res.metadata.namespace, res.metadata.name, { foo: 'bar' })
      obj = get_object(res)
      annotations = obj.dig(*%w(metadata annotations))
      expect(annotations).to include('foo' => 'bar')
    ensure
      safely_delete_res(res)
    end

    it 'does not overwrite annotations when option is given' do
      cli.apply(res)
      cli.annotate('ConfigMap', res.metadata.namespace, res.metadata.name, { foo: 'bar' })
      expect {
        cli.annotate('ConfigMap', res.metadata.namespace, res.metadata.name, { foo: 'baz' }, overwrite: false)
      }.to raise_error(KubernetesCLI::AnnotateResourceError)
      obj = get_object(res)
      annotations = obj.dig(*%w(metadata annotations))
      expect(annotations).to include('foo' => 'bar')
    ensure
      safely_delete_res(res)
    end
  end

  describe '#logtail' do
    let(:namespace) { 'namespace' }
    let(:selector) { { role: 'web' } }

    it 'includes the path to the kubeconfig' do
      fake_cli.logtail(namespace, selector)
      expect(fake_cli).to run_exec.with_args(['--kubeconfig', kubeconfig_path])
    end

    it 'includes the selector' do
      fake_cli.logtail(namespace, selector)
      expect(fake_cli).to run_exec.with_args(['--selector', 'role=web'])
    end

    it 'follows log output by default' do
      fake_cli.logtail(namespace, selector)
      expect(fake_cli).to run_exec.with_args(['-f'])
    end

    it "doesn't follows log output when asked" do
      fake_cli.logtail(namespace, selector, follow: false)
      expect(fake_cli).to run_exec.without_args(['-f'])
    end
  end

  describe '#current_context' do
    it 'fetches the current context' do
      expect(cli.current_context).to eq('kind-kubernetes-cli-tests')
    end
  end

  describe '#api_resources' do
    it 'gets the set of available API resources' do
      api_resources = cli.api_resources
      pairs = api_resources.split("\n").map { |line| line.split(/[\s]+/)[0...2] }
      expect(pairs).to include(['namespaces', 'ns'])
      expect(pairs).to include(['configmaps', 'cm'])
    end
  end

  describe '#restart_deployment' do
    it 'restarts the deployment' do
      cli.apply(deployment)
      wait_for_deployment(deployment)

      obj_v1 = get_object(deployment)
      expect(obj_v1.dig(*%w(status observedGeneration))).to eq(1)

      cli.restart_deployment(
        deployment.metadata.namespace,
        deployment.metadata.name
      )

      obj_v2 = get_object(deployment)
      expect(obj_v2.dig(*%w(status observedGeneration))).to eq(2)
    ensure
      safely_delete_res(deployment)
    end
  end

  def wait_for_deployment(depl)
    start = Time.now

    loop do
      obj = get_object(depl)
      desired = obj.dig(*%w(status replicas))
      updated = obj.dig(*%w(status updatedReplicas))
      available = obj.dig(*%w(status availableReplicas))

      if updated == desired && updated == available
        break
      else
        if (Time.now - start) > 60
          raise 'timed out waiting for deployment'
        end

        sleep 1
      end
    end

    start = Time.now

    loop do
      obj = get_object(depl)
      pods = begin
        cli.get_objects(
          'Pod',
          deployment.metadata.namespace,
          deployment.spec.selector.match_labels.kv_pairs
        )
      rescue KubernetesCLI::GetResourceError
        []
      end

      pod_phases = pods.map { |p| p.dig(*%w(status phase)) }

      if pods.size == obj.dig(*%w(status replicas)) && pod_phases.all?('Running')
        break
      else
        if (Time.now - start) > 60
          raise 'timed out waiting for pods'
        end

        sleep 1
      end
    end
  end

  def delete_res(res)
    kind = res.to_resource.contents[:kind]
    cli.delete_object(kind, res.metadata.namespace, res.metadata.name)
  end

  def safely_delete_res(res)
    delete_res(res)
  rescue KubernetesCLI::DeleteResourceError
  end

  def get_object(res)
    kind = res.to_resource.contents[:kind]
    cli.get_object(kind, res.metadata.namespace, res.metadata.name)
  end
end