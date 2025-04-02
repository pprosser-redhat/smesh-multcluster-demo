# Multi Primary, Multi Network Istio demon 
## Configuration Notes


**Note:** Need to make sure the OpenShift clusters are confirgured with Load Balancers, istio discovers the IP of the east west gateway in the other cluster so the k8s service is defined as loadbalancer

**Note:** The easiest way to ensure this demo works is to deploy the clusters into different regions. 

#### Install the Operators

Operators required in both clusters

- Red Hat OpenShift Service Mesh 3
- Tempo Operator
- Red Hat Build of OpenTelemetry 
- Kiali Operator
- cert-manger (if doing connectivity link)

Followed the *[install documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_service_mesh/3.0/html/installing/ossm-multi-cluster-topologies#ossm-multi-cluster-configuration-overview_ossm-multi-cluster-topologies)* to create the meshes and setup the east west gateways. 

**Note:** Not documented - make sure an IstioCNI crd instance is created in both clusters. I created this in namespace istio-cni

Here's the one I created 

```
apiVersion: sailoperator.io/v1alpha1
kind: IstioCNI
metadata:
  name: default
spec:
  namespace: istio-cni
  version: 1.24.3
```
or for faster installation, use the scripts.

There are 2 scripts, one for east and west clusters.

For basic installation,

cd East_Cluster and run
```
oc login -u https://<east_cluster_api_server_url>
./install_ossm3_demo.sh
```

cd West_Cluster and run
```
oc login -u https://<west_cluster_api_server_url>
./install_ossm3_demo.sh
```
Before running the scripts do the following 

```
oc login -u https://<east_cluster_api_server_url>
```
```
export CTX_CLUSTER1=$(oc config current-context)
```
```
oc login -u https://<west_cluster_api_server_url>
```
```
export CTX_CLUSTER2=$(oc config current-context)
```
now, run 

```
./deploy_east_west_configuration.sh
```

Before verifying the configuration, make sure a podmonitor is added to the applications namespace e.g. sample, and superhereoes

Verify the configuration, using the guide in the *[documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_service_mesh/3.0/html/installing/ossm-multi-cluster-topologies#ossm-verifying-multi-cluster-topology_ossm-multi-cluster-topologies)*

**Note:** V1 of helloworld is deployed on the east cluster (cluster 1) and V2 of the helloworld is deployed on the west cluster (cluster 2).

## Install Monitor (Not Mandatory)

While installing the monitoring stackis not needed for the demo, it is powerful in that it shows both clusters and the traffic flowing automatically between them. Makes it easier to explain whats going on. 

Monitoring is installed as part of the automatic script

## Simple demo using the standard helloworld demo.

### Set up the terminal ready

During the demo, you will need to access 2 OpenShift clusters, to make this easier, we will use the OpenShift cli option "context"

#### On the command line, login to your east cluster 

```
oc login -u https://<east_cluster_api_server_url>
```

set the context to an environment variable 

```
export CTX_CLUSTER1=$(oc config current-context)
```
#### On the command line, login to your west cluster

```
oc login -u https://<west_cluster_api_server_url>
```

set the context to an environment variable 

```
export CTX_CLUSTER2=$(oc config current-context)
```


### Run the demo

The simple demo just using a Helloworld container, that is called by a sleep container. Both are injected with Istio Proxies.

It is based on the application you used to verify the multi cluster setup is working

#### Load Balancing Demo with failover

Assuming the Install has gone well, in the terminal window, run 

```
for i in {0..100}; do \
  oc --context="${CTX_CLUSTER1}" exec -n sample deploy/sleep -c sleep -- curl -sS helloworld.sample:5000/hello; \
done
```

Assuming all is good, you see see output similar to that below:

![Load balance output](/images/screenshot1.png)

This is demonstrating the service being load balanced across the clusters.

Simulate a failure.....

run the following again (if it has finished)

```
for i in {0..100}; do \
  oc --context="${CTX_CLUSTER1}" exec -n sample deploy/sleep -c sleep -- curl -sS helloworld.sample:5000/hello; \
done
```
In another terminal window, make sure you have set the contexts as described [here](#set-up-the-terminal-ready).

In the new terminal window type

```
oc scale deployment helloworld-v1 --replicas=0 -n=sample --context="${CTX_CLUSTER1}"
```

You can of course use the OpenShift console to scale to replicas if you wish.

You should now see that all responses are coming from Cluster 2 as below

![Load balance output](/images/screenshot2.png)

Make sure the test is still running, if not, start it again

```
for i in {0..100}; do \
  oc --context="${CTX_CLUSTER1}" exec -n sample deploy/sleep -c sleep -- curl -sS helloworld.sample:5000/hello; \
done
```

In the other terminal window, type the following 

```
oc scale deployment helloworld-v1 --replicas=1 -n=sample --context="${CTX_CLUSTER1}"
```

You should see the test start load balancing the requests again (once hellworld-v1 restarts)

#### Locality demo with service failover

Multi Cluster has a concept called locality. It ensures that under normal operation, serivce calls occur within the cluster, calls to the second cluster are only made in the event of service failure in the current cluster.


To configure this, a destination rule needs to be deployed to both the east and west cluster.

This allows the east cluster to fail to the west, and the west cluster to fail to the east.


To get locality working, the process can use the region, zone, and subzones to determine the locality.

You can explicity set the failover to and froms for failure, but to keep thjis demo simple, it will determin locality itself. 

Create the following destination rule on the east cluster

```
cat <<EOF | oc --context "${CTX_CLUSTER1}" apply -f -
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: helloworld
  namespace: sample
spec:
  host: helloworld.sample.svc.cluster.local
  trafficPolicy:
    connectionPool:
      http:
        maxRequestsPerConnection: 1
    loadBalancer:
      localityLbSetting:
        enabled: true
      simple: ROUND_ROBIN
    outlierDetection:
      baseEjectionTime: 1m
      consecutive5xxErrors: 1
      interval: 1s
EOF
```

and put the same destination rule into the west cluster as below

```
cat <<EOF | oc --context "${CTX_CLUSTER2}" apply -f -
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: helloworld
  namespace: sample
spec:
  host: helloworld.sample.svc.cluster.local
  trafficPolicy:
    connectionPool:
      http:
        maxRequestsPerConnection: 1
    loadBalancer:
      localityLbSetting:
        enabled: true
      simple: ROUND_ROBIN
    outlierDetection:
      baseEjectionTime: 1m
      consecutive5xxErrors: 1
      interval: 1s
EOF
```

This ensures that both clusters keep traffic within their clusters unless there is a failure on one side. In that case traffic will failover to the other cluster.


##### Test on the east cluster

run the following in one of your terminal windows 

```
for i in {0..100}; do \
  oc --context="${CTX_CLUSTER1}" exec -n sample deploy/sleep -c sleep -- curl -sS helloworld.sample:5000/hello; \
done
```
Even though both clusters have an active helloworld service, you only see responses from helloworld-v1

If the test is still running, press ctl-c to stop it.

##### Test on the west cluster

```
for i in {0..100}; do \
  oc --context="${CTX_CLUSTER2}" exec -n sample deploy/sleep -c sleep -- curl -sS helloworld.sample:5000/hello; \
done
```

You should now only see responses from helloworld-v2. Locality in action!

##### Test failover on the east cluster

Run 

```
for i in {0..100}; do \
  oc --context="${CTX_CLUSTER1}" exec -n sample deploy/sleep -c sleep -- curl -sS helloworld.sample:5000/hello; \
done
```
As before, all responses should becoming from hello-world-v1

Now, reduce the replicas to zero for hello-world-v1 on the east cluster

```
oc scale deployment helloworld-v1 --replicas=0 -n=sample --context="${CTX_CLUSTER1}"
```
You should see the responses start coming from hello-world-v2

(failure in action)

Restart helloworld-v1

```
oc scale deployment helloworld-v1 --replicas=1 -n=sample --context="${CTX_CLUSTER1}"
```

Once it has started , you should see it revert to helloworld-v1


SUPERHEROES is still work in progress

### Getting Superheroes to work with Istio

Create the super hereoes project in both clusters 

```
oc new-project superheroes --context="${CTX_CLUSTER1}"
```
```
oc new-project superheroes --context="${CTX_CLUSTER2}"
```

Make sure you label the clusters 

Label the projects in both cluster for Istio injection
```
oc label namespace superheroes istio-injection=enabled --context="${CTX_CLUSTER1}"
```
```
oc label namespace superheroes istio-injection=enabled --context="${CTX_CLUSTER2}"
```

Make sure you create the podmonitor in each project 

```
oc apply --context="${CTX_CLUSTER1} -f ./East_Cluster/resources/Monitoring/podMonitor.yaml
```
```
oc apply --context="${CTX_CLUSTER2} -f ./West_Cluster/resources/Monitoring/podMonitor.yaml
```

Deployed a gateway in the superheroes project as per the deploying gateways documentation 

Add configuration required before deploying the gateway

```
apiVersion: v1
kind: ServiceAccount
metadata:
  name: secret-reader
  namespace: superheroes
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: secret-reader
  namespace: superheroes
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "watch", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name:  secret-reader
  namespace: superheroes
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: secret-reader
subjects:
  - kind: ServiceAccount
    name:  secret-reader
```


Here's the Gateway Deployment 
```
kind: Deployment
apiVersion: apps/v1
metadata:
  name: superheroes-gw
  namespace: superheroes
spec:
  replicas: 1
  selector:
    matchLabels:
      istio: superheroes-gw
  template:
    metadata:
      creationTimestamp: null
      labels:
        istio: superheroes-gw
        sidecar.istio.io/inject: 'true'
      annotations:
        inject.istio.io/templates: gateway
    spec:
      containers:
        - name: istio-proxy
          image: auto
          ports:
            - name: http-envoy-prom
              containerPort: 15090
              protocol: TCP
          resources:
            limits:
              cpu: '2'
              memory: 1Gi
            requests:
              cpu: 100m
              memory: 128Mi
          terminationMessagePath: /dev/termination-log
          terminationMessagePolicy: File
          imagePullPolicy: Always
          securityContext:
            capabilities:
              drop:
                - ALL
            privileged: false
            runAsNonRoot: true
            readOnlyRootFilesystem: true
            allowPrivilegeEscalation: false
      restartPolicy: Always
      terminationGracePeriodSeconds: 30
      dnsPolicy: ClusterFirst
      serviceAccountName: secret-reader
      serviceAccount: secret-reader
      securityContext:
        sysctls:
          - name: net.ipv4.ip_unprivileged_port_start
            value: '0'
      schedulerName: default-scheduler
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 25%
      maxSurge: 25%
  revisionHistoryLimit: 10
  progressDeadlineSeconds: 600
```
Service deployment
```
kind: Service
apiVersion: v1
metadata:
  name: superheroes-gw
  namespace: superheroes
spec:
  clusterIP: 172.30.82.131
  ipFamilies:
    - IPv4
  ports:
    - name: status-port
      protocol: TCP
      port: 15021
      targetPort: 15021
    - name: http
      protocol: TCP
      port: 80
      targetPort: 80
    - name: https
      protocol: TCP
      port: 443
      targetPort: 443
  internalTrafficPolicy: Cluster
  clusterIPs:
    - 172.30.82.131
  type: ClusterIP
  ipFamilyPolicy: SingleStack
  sessionAffinity: None
  selector:
    istio: superheroes-gw
```
and a route 

```
kind: Route
apiVersion: route.openshift.io/v1
metadata:
  name: superheroes-gw
  namespace: superheroes
spec:
  host: superheroes.apps.cluster-66vch.66vch.gcp.redhatworkshops.io
  to:
    kind: Service
    name: superheroes-gw
    weight: 100
  port:
    targetPort: http
  wildcardPolicy: None
```

and the Istio Gateway definition 


```
kind: Gateway
apiVersion: networking.istio.io/v1
metadata:
  name: superheroes-gateway
  namespace: superheroes
spec:
  servers:
  - port:
      number: 80
      protocol: HTTP
      name: http-80
    hosts:
    - superheroes.apps.cluster-66vch.66vch.gcp.redhatworkshops.io
  selector:
    istio: superheroes-gw
status: {}

```

To get everything working, all databases in the Superheroes database needed to be labelled in the spec.template section with

```
sidecar.istio.io/inject: 'false'
```

To get the gateway routing correctly, I needed to create a Virtual Service

```
kind: VirtualService
apiVersion: networking.istio.io/v1
metadata:
  name: superheroes-ui
  namespace: superheroes
spec:
  hosts:
  - superheroes.apps.cluster-66vch.66vch.gcp.redhatworkshops.io
  gateways:
  - superheroes/superheroes-gateway
  http:
  - match:
    - uri:
        prefix: /api/fights
    route:
    - destination:
        host: rest-fights.superheroes.svc.cluster.local
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        host: ui-super-heroes.superheroes.svc.cluster.local
```

#### Note

To enable the Location microsservice to work correctly the K8s service has to be changed slighly.

rather than :

```
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 8089
```

the port name need to be changed to grpc to allow Istio to perform its magic

```
  ports:
    - name: grpc
      protocol: TCP
      port: 80
      targetPort: 8089
```


To enable, locality to work, you have to switch off the quarkus service discovery feature using stork.

Apply the following to the east cluster 

```
oc patch configmap rest-fights-config -p '{"data":{"quarkus.rest-client.hero-client.url":"http://rest-heroes","quarkus.rest-client.narration-client.url":"http://rest-narration","fight.villain.client-base-url":"http://rest-villains"}}' -n superheroes --context="${CTX_CLUSTER1}"
```

and apply the following to the west cluster

```
oc patch configmap rest-fights-config -p '{"data":{"quarkus.rest-client.hero-client.url":"http://rest-heroes","quarkus.rest-client.narration-client.url":"http://rest-narration","fight.villain.client-base-url":"http://rest-villains"}}' -n superheroes --context="${CTX_CLUSTER2}"
```

Restart pods in the superheroes project

```
oc delete pods --all -n superheroes --context="${CTX_CLUSTER1}"
```


For locality awareness and failover create the following destination rule 

```
cat <<EOF | oc --context "${CTX_CLUSTER2}" apply -f -
---
kind: DestinationRule
apiVersion: networking.istio.io/v1
metadata:
  name: superheroes-apicurio
  namespace: superheroes
spec:
  host: apicurio
  trafficPolicy:
    loadBalancer:
      simple: ROUND_ROBIN
      localityLbSetting:
        enabled: true
    connectionPool:
      http:
        maxRequestsPerConnection: 1
    outlierDetection:
      consecutive5xxErrors: 1
      interval: 1s
      baseEjectionTime: 60s
---
kind: DestinationRule
apiVersion: networking.istio.io/v1
metadata:
  name: superheroes-event-statistics
  namespace: superheroes
spec:
  host: event-statistics
  trafficPolicy:
    loadBalancer:
      simple: ROUND_ROBIN
      localityLbSetting:
        enabled: true
    connectionPool:
      http:
        maxRequestsPerConnection: 1
    outlierDetection:
      consecutive5xxErrors: 1
      interval: 1s
      baseEjectionTime: 60s
---
kind: DestinationRule
apiVersion: networking.istio.io/v1
metadata:
  name: superheroes-fights-db
  namespace: superheroes
spec:
  host: fights-db
  trafficPolicy:
    loadBalancer:
      simple: ROUND_ROBIN
      localityLbSetting:
        enabled: true
    connectionPool:
      http:
        maxRequestsPerConnection: 1
    outlierDetection:
      consecutive5xxErrors: 1
      interval: 1s
      baseEjectionTime: 60s
---
kind: DestinationRule
apiVersion: networking.istio.io/v1
metadata:
  name: superheroes-fights-kafka
  namespace: superheroes
spec:
  host: fights-kafka
  trafficPolicy:
    loadBalancer:
      simple: ROUND_ROBIN
      localityLbSetting:
        enabled: true
    connectionPool:
      http:
        maxRequestsPerConnection: 1
    outlierDetection:
      consecutive5xxErrors: 1
      interval: 1s
      baseEjectionTime: 60s
---
kind: DestinationRule
apiVersion: networking.istio.io/v1
metadata:
  name: superheroes-grpc-locations
  namespace: superheroes
spec:
  host: grpc-locations
  trafficPolicy:
    loadBalancer:
      simple: ROUND_ROBIN
      localityLbSetting:
        enabled: true
    connectionPool:
      http:
        maxRequestsPerConnection: 1
    outlierDetection:
      consecutive5xxErrors: 1
      interval: 1s
      baseEjectionTime: 60s
---
kind: DestinationRule
apiVersion: networking.istio.io/v1
metadata:
  name: superheroes-heroes-db
  namespace: superheroes
spec:
  host: heroes-db
  trafficPolicy:
    loadBalancer:
      simple: ROUND_ROBIN
      localityLbSetting:
        enabled: true
    connectionPool:
      http:
        maxRequestsPerConnection: 1
    outlierDetection:
      consecutive5xxErrors: 1
      interval: 1s
      baseEjectionTime: 60s
---
kind: DestinationRule
apiVersion: networking.istio.io/v1
metadata:
  name: superheroes-locations-db
  namespace: superheroes
spec:
  host: locations-db
  trafficPolicy:
    loadBalancer:
      simple: ROUND_ROBIN
      localityLbSetting:
        enabled: true
    connectionPool:
      http:
        maxRequestsPerConnection: 1
    outlierDetection:
      consecutive5xxErrors: 1
      interval: 1s
      baseEjectionTime: 60s
---
kind: DestinationRule
apiVersion: networking.istio.io/v1
metadata:
  name: superheroes-rest-fights
  namespace: superheroes
spec:
  host: rest-fights
  trafficPolicy:
    loadBalancer:
      simple: ROUND_ROBIN
      localityLbSetting:
        enabled: true
    connectionPool:
      http:
        maxRequestsPerConnection: 1
    outlierDetection:
      consecutive5xxErrors: 1
      interval: 1s
      baseEjectionTime: 60s
---
kind: DestinationRule
apiVersion: networking.istio.io/v1
metadata:
  name: superheroes-rest-heroes
  namespace: superheroes
spec:
  host: rest-heroes
  trafficPolicy:
    loadBalancer:
      simple: ROUND_ROBIN
      localityLbSetting:
        enabled: true
    connectionPool:
      http:
        maxRequestsPerConnection: 1
    outlierDetection:
      consecutive5xxErrors: 1
      interval: 1s
      baseEjectionTime: 60s
---
kind: DestinationRule
apiVersion: networking.istio.io/v1
metadata:
  name: superheroes-rest-narration
  namespace: superheroes
spec:
  host: rest-narration
  trafficPolicy:
    loadBalancer:
      simple: ROUND_ROBIN
      localityLbSetting:
        enabled: true
    connectionPool:
      http:
        maxRequestsPerConnection: 1
    outlierDetection:
      consecutive5xxErrors: 1
      interval: 1s
---
kind: DestinationRule
apiVersion: networking.istio.io/v1
metadata:
  name: superheroes-rest-villains
  namespace: superheroes
spec:
  host: rest-villains
  trafficPolicy:
    loadBalancer:
      simple: ROUND_ROBIN
      localityLbSetting:
        enabled: true
    connectionPool:
      http:
        maxRequestsPerConnection: 1
    outlierDetection:
      consecutive5xxErrors: 1
      interval: 1s
      baseEjectionTime: 60s
---
kind: DestinationRule
apiVersion: networking.istio.io/v1
metadata:
  name: superheroes-superheroes-gw
  namespace: superheroes
spec:
  host: superheroes-gw
  trafficPolicy:
    loadBalancer:
      simple: ROUND_ROBIN
      localityLbSetting:
        enabled: true
    connectionPool:
      http:
        maxRequestsPerConnection: 1
    outlierDetection:
      consecutive5xxErrors: 1
      interval: 1s
      baseEjectionTime: 60s
---
kind: DestinationRule
apiVersion: networking.istio.io/v1
metadata:
  name: superheroes-ui-super-heroes
  namespace: superheroes
spec:
  host: ui-super-heroes
  trafficPolicy:
    loadBalancer:
      simple: ROUND_ROBIN
      localityLbSetting:
        enabled: true
    connectionPool:
      http:
        maxRequestsPerConnection: 1
    outlierDetection:
      consecutive5xxErrors: 1
      interval: 1s
      baseEjectionTime: 60s
---
kind: DestinationRule
apiVersion: networking.istio.io/v1
metadata:
  name: superheroes-villains-db
  namespace: superheroes
spec:
  host: villains-db
  trafficPolicy:
    loadBalancer:
      simple: ROUND_ROBIN
      localityLbSetting:
        enabled: true
    connectionPool:
      http:
        maxRequestsPerConnection: 1
    outlierDetection:
      consecutive5xxErrors: 1
      interval: 1s
      baseEjectionTime: 60s
EOF
```
### Tracing 

Install the Tempo operator in both clusters

Install the Red Hat build of OpenTelemetry operator in both clusters

Creeate project called "tempo" in both clusters

Setup s3 bucket and create secret 

```
kind: Secret
apiVersion: v1
metadata:
  name: s3-test
  namespace: tempo
stringData:
  access_key_id: <AWS_Key>
  access_key_secret: <AWS secret key>
  bucket: <bucketname>
  endpoint: https://s3.eu-west-1.amazonaws.com
type: Opaque
```
Merge the following in to tracing for Kiali 

s3://philtempo1/test/
https://philtempo1.s3.eu-west-1.amazonaws.com/test/
```
spec:
  external_services:
    tracing:
      enabled: true 
      provider: tempo 
      use_grpc: false
      internal_url: https://tempo-sample-query-frontend.tempo.svc.cluster.local:3200/api/traces/v1/default/tempo 
      external_url: https://tempo-sample-query-frontend-tempo.apps.cluster-zpfc2.zpfc2.sandbox1030.opentlc.com/api/traces/v1/default/search 
      health_check_url: https://tempo-sample-query-frontend-tempo.apps.cluster-zpfc2.zpfc2.sandbox1030.opentlc.com/api/traces/v1/north/tempo/api/echo 
      auth: 
        ca_file: /var/run/secrets/kubernetes.io/serviceaccount/service-ca.crt
        insecure_skip_verify: false
        type: bearer
        use_kiali_token: true
      tempo_config:
         url_format: "jaeger" 
```