# Installing the Prometheus Operator

You may skip this step if you have already installed the Prometheus Operator

## Step 1: Installing the Prometheus Operator

- Create a new namespace for Prometheus Operator using the following command:

```bash
kubectl create namespace monitoring
```

- Add the Prometheus Operator Helm repository:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
```

- Install the Prometheus Operator using the following command:

```bash
helm install prometheus-operator prometheus-community/kube-prometheus-stack --namespace monitoring
```

## Step 2: Verifying the Deployment

- Verify the deployment of the Prometheus Operator using the following command:

```bash
kubectl get pods -n monitoring
```

## Step 3: Accessing the Prometheus Dashboard

- Check the service endpoints of Prometheus and Grafana.

```bash
kubectl get svc -n monitoring
```

- Use port forwarding to access the Prometheus dashboard locally

```bash
kubectl port-forward svc/prometheus-operator-kube-p-prometheus -n monitoring 9090:9090
```

And you can access the Prometheus dashboard by opening "http://localhost:9090" in your browser.

- Similarly, use port forwarding to access the Grafana dashboard locally

```bash
kubectl port-forward svc/prometheus-operator-grafana -n monitoring 3000:80
```

and you can access the Grafana dashboard by opening "http://localhost:3000" in your browser.

To login, you may retrieve the credential from the secret:

```bash
kubectl get secrets prometheus-operator-grafana -n monitoring -oyaml
```