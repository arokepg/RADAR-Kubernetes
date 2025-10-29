# Development Guide

## Table of Contents

<!-- TOC -->
* [Development Guide](#development-guide)
  * [Table of Contents](#table-of-contents)
  * [Development automation](#development-automation)
        * [Containerd](#containerd)
  * [Adding a new component to RADAR-Kuberentes](#adding-a-new-component-to-radar-kuberentes)
  * [Testing the changes](#testing-the-changes)
<!-- TOC -->

## Development automation

This repository can be used for development automation for instance on a k3s or k3d (dockerized k3s) cluster. The
example below shows how to deploy on a k3d cluster.

1. Install k3d (see [here](https://github.com/k3d-io/k3d#get))
2. Create a k3d cluster that is configured to run RADAR-base:

```shell
k3d cluster create my-test-cluster --config=dev/k3d-dev.yaml
```

This example creates a cluster named `my-test-cluster` with a load balancer that forwards local port 80 to the cluster.
The configuration file `dev/k3d-dev.yaml` is used to configure the cluster. This cluster will be accessible
in _kubectl_ with context name _k3d-my-test-cluster_.

##### Containerd

When you use [containerd](https://www.docker.com/blog/containerd-vs-docker) combined with docker, you can speed up the
deployment by using a local pull-through registry and with docker image layers cached on the host (in directory
`$HOME/k3d-containerd`:

```shell
k3d cluster create my-test-cluster --config=dev/k3d-dev-containerd.yaml
```

3. Initialize the RADAR-Kubernetes deployment. Run:

```shell
./bin/init
```

4. In file _etc/production.yaml_:

- set _kubeContext_ to _k3d-my-test-cluster_
- set _dev_deployment_ to _true_
- (optional) enable/disable components as needed with the __install_ fields

5. Install RADAR-Kubernetes on the k3d cluster:

```shell
helmfile sync
```

When installation is complete, you can access the applications at `http://localhost`.

## Adding a new component to RADAR-Kuberentes

In order to add a new component you first need to add its helm chart
to [radar-helm-charts)](https://github.com/RADAR-base/radar-helm-charts) repository. Refer to contributing guidelines of
that repository for more information. Once the chart has been added you need to:

- Add a helmfile for it in `helmfile.d` directory. The helmfiles are seperated in a modular way in order to avoid having
  a huge file and also installing certain components in order. Have a look at the current helmfiles and if your
  component is related to one of them add your component in that file other file create a new file. If your component is
  a dependency to other components, like Kafka or PostgreSQL prefix the file name with a smaller number so it will be
  installed first, but if it's a standalone component, the prefix number can be higher.
- Add release to helmfile. Depending on the helm chart this can mostly be copy pasted from other releases and change
  names to your component. If you've added custom values files in `etc` directory make sure to reference them in the
  release.
- Add a basic configuration of it to `etc/base.yaml` which should include at least `_install`, `_chart_version` and
  `_extra_timeout` values. In order to keep the `base.yaml` short, only add configurations that the user will most
  likely to change during installation.
- If your component is dealing with credentials, the values in the helm charts that refer to that has to be added to
  `etc/base-secrets.yaml` file.
- If the credentials isn't something external and can be auto-generated be sure to add it to `bin/generate-secrets`,
  following examples of the current credentials
- If the user has to input a file to the helm chart, add the relavant key to the `base.yaml.gotmpl` file.
- If the component that you're adding is an external component and you want it to have some default configuration,
  create a folder with its name in `etc` directory and add the default configuration there in a YAML file and refer to
  that configuration in the helmfile of the component.

## Testing the changes

In order to test the changes locally you can use helmfile command to install the component in your cluster. You can make
installation faster if you only select your component to install:

```
helmfile apply --file helmfile.d/name-of-the-helmfile.yaml --selector name=name-of-the-component
```

You can also use other the helmfile commands like `helmfile template` and `helmfile diff` to see what is being applied
to the cluster.
