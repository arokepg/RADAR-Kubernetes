# Scaling Strimzi Kafka brokers and using Cruise Control in RADAR-Kubernetes

This guide explains how to change the number of Strimzi Kafka brokers managed by RADAR-Kubernetes and how to use Strimzi
Cruise Control to rebalance partitions and leaders after scaling.

The RADAR-Kubernetes Helmfile deploys Kafka via the radar/radar-kafka chart (Strimzi-based). The number of brokers and
related topic settings are driven by values in etc/base.yaml or etc/production.yaml.

## Prerequisites

- kubectl is configured to point to your RADAR-Kubernetes cluster (see kubeContext in your values file).
- helmfile is installed and you can run helmfile sync from the repository root.
- Your Kafka cluster is deployed with the radar-kafka release (default in this repository).

## Changing the number of Kafka brokers

You can change the number of Strimzi Kafka brokers by updating kafka_num_brokers and applying the configuration.

1) Edit value `num_kafka_brokers` in your `etc/production.yaml` file

Example:

```
kafka_num_brokers: 6
```

2) Apply the change

From the repository root, run:

```
helmfile sync -lname=radar-kafka
```

This updates the Strimzi Kafka Custom Resource via the radar-kafka Helm release and scales the node pool up or down.

3) Verify broker Pods

```
# Expect radar-kafka-node-pool-0 .. radar-kafka-node-pool-(N-1)
kubectl get pods -l strimzi.io/name=radar-kafka-kafka -o wide
```

If you scaled up, new brokers should appear and join the cluster. If you scaled down, Strimzi will roll the cluster and
remove the extra Pods.

### Notes for scaling up vs. down

- Scaling up: increase kafka_num_brokers and run helmfile sync. Use Cruise Control (below) to rebalance partitions and
  leaders so the new brokers are utilized.
- Scaling down: first ensure kafka_num_in_sync_brokers and kafka_num_topic_replicas are not larger than the new broker
  count. Reduce those if needed, apply helmfile sync, and only then reduce kafka_num_brokers. After the scale down, run
  a Cruise Control rebalance to redistribute partitions and leaders.

## Using Strimzi Cruise Control for rebalancing

Strimzi integrates Cruise Control and exposes a KafkaRebalance Custom Resource (CR) to request and manage rebalances.

### Check that Cruise Control is running

```
kubectl get pods -l strimzi.io/name=radar-kafka-cruise-control
```

You should see a Pod like radar-kafka-cruise-control-... If not, ensure your radar-kafka chart enables Cruise Control (
this is not enabled by default in RADAR-Kubernetes deployments of Strimzi). To enable Cruise Control, set in `etc/production.yaml`:

```
radar_kafka_stack:
  kafka:
    cruiseControl:
      enabled: true
```

### Typical rebalance workflow

1) Create a KafkaRebalance CR to get a proposal

Save the following as rebalance.yaml:

```
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaRebalance
metadata:
  name: rebalance-$(date +%Y%m%d-%H%M%S)
  labels:
    strimzi.io/cluster: radar-kafka
spec:
  # goals is optional; if omitted, Strimzi/Cruise Control uses its defaults
  # goals:
  #   - RackAwareGoal
  #   - ReplicaCapacityGoal
  #   - DiskCapacityGoal
  #   - NetworkInboundCapacityGoal
  #   - NetworkOutboundCapacityGoal
  #   - CpuCapacityGoal
  #   - ReplicaDistributionGoal
  #   - PotentialNwOutGoal
  #   - LeaderReplicaDistributionGoal
  #   - TopicReplicaDistributionGoal
  skipHardGoalCheck: false
```

Apply it:

```
kubectl apply -f rebalance.yaml
```

2) Inspect the proposal

```
kubectl get kafkarebalance -o wide
kubectl describe kafkarebalance <name>
```

When the KafkaRebalance enters the ProposalReady state, Cruise Control has a plan ready.

3) Approve the rebalance

```
kubectl annotate kafkarebalance <name> strimzi.io/rebalance=approve --overwrite
```

Cruise Control will execute the plan. Track progress:

```
kubectl get kafkarebalance <name> -o yaml
kubectl logs deploy/radar-kafka-cruise-control
```

4) Optional: stop/cancel an ongoing rebalance

```
kubectl annotate kafkarebalance <name> strimzi.io/rebalance=stop --overwrite
```

### Remove or drain specific brokers

When scaling down or removing a particular broker, you can ask Cruise Control to move partitions off selected brokers
first.

Example remove-brokers request (drains brokers 2 and 3):

```
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaRebalance
metadata:
  name: remove-brokers-2-3
  labels:
    strimzi.io/cluster: radar-kafka
spec:
  mode: remove-brokers
  brokers: [2, 3]
  skipHardGoalCheck: false
```

Apply and, once in ProposalReady, approve as above. After completion and when ISR/leader distribution looks healthy, you
can reduce kafka_num_brokers and run helmfile sync to actually remove those brokers.

### Monitoring and validation

- Check broker utilization and partition distribution in Cruise Control logs:
  `kubectl logs deploy/radar-kafka-cruise-control`.
- Verify partition distribution and leaders:
  -
  `kubectl exec -it radar-kafka-node-pool-0 -c kafka -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --describe | head -n 100`
- Ensure no under-replicated partitions remain:
  -
  `kubectl exec -it radar-kafka-node-pool-0 -c kafka -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --describe | grep -i under-replicated | wc -l`

## Quick reference: applying changes and testing

- Apply any configuration changes:
  - `helmfile sync`
- Install or update only Kafka-related releases (optional):
  - `helmfile apply --file helmfile.d/10-services.yaml --selector name=radar-kafka`
- Diff before applying (optional):
  - `helmfile diff --file helmfile.d/10-services.yaml --selector name=radar-kafka`

## Related: Adding new components and testing changes

For general guidance on adding new components and testing, see Development Guide:

- Adding a new component to RADAR-Kuberentes
- Testing the changes

Those sections cover how to contribute new Helm releases and how to use helmfile apply/template/diff during development.
