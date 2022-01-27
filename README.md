## kubernetes-cli

![Unit Tests](https://github.com/getkuby/kuby-core/actions/workflows/unit_tests.yml/badge.svg?branch=master)
![Integration Tests](https://github.com/getkuby/kuby-core/actions/workflows/integration_tests.yml/badge.svg?branch=master)

A Ruby wrapper around the Kubernetes CLI.

### Usage

Create a new instance by passing the path to your Kube config (usually ~/.kube/config) and optionally the path to the kubectl executable (by default, the executable path comes from the [kubectl-rb gem](https://github.com/getkuby/kubectl-rb)).

```ruby
cli = KubernetesCLI(File.join(ENV['HOME'], '.kube', 'config'))
```

### Available Methods

- `annotate`
- `api_resources`
- `apply`
- `apply_uri`
- `current_context`
- `delete_object`
- `delete_objects`
- `exec_cmd`
- `executable`
- `get_object`
- `get_objects`
- `kubeconfig_path`
- `last_status`
- `logtail`
- `patch_object`
- `restart_deployment`
- `run_cmd`
- `system_cmd`

Please see the source code for available options.

## Running Tests

`bundle exec rspec` should do the trick. Requires that you have Docker installed.

## License

Licensed under the MIT license. See LICENSE for details.

## Authors

* Cameron C. Dutro: http://github.com/camertron
