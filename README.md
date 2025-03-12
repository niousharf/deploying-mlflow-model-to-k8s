# Guide to Deploying an MLflow Model to a Kubernetes Cluster Using KServe

For official MLflow deployment documentation, refer to the [MLflow Docs](https://mlflow.org/docs/latest/deployment/deploy-model-locally/).

## Why KServe?
MLflow offers a Flask-based inference server for easy model deployment, which can be containerized and deployed to Kubernetes. However, this approach is not ideal for production due to Flask's limitations in scalability and performance. To address these issues, MLflow integrates with [MLServer](https://www.google.com/url?sa=t&source=web&rct=j&opi=89978449&url=https://mlserver.readthedocs.io/en/latest/getting-started/index.html&ved=2ahUKEwjbxYqzl4OMAxUJHzQIHW-lBHoQFnoECBkQAQ&usg=AOvVaw0LYOLhvBnH3NfdwTh6DTvz), a more robust inference engine designed for large-scale deployments. MLServer enables seamless, one-step deployment to Kubernetes-based frameworks like [KServe](https://kserve.github.io/website/latest/).

## Setup Poetry
Follow the instructions in my other [GitHub repo README](https://github.com/niousharf/chatbot-proj/tree/master) to set up Poetry.

## Setup a Kubernetes Cluster
### Kubernetes Cluster
If you already have access to a Kubernetes cluster, you can install KServe to your cluster by following the official [installation instructions](https://github.com/kserve/kserve#hammer_and_wrench-installation).
### Local Kubernetes Cluster Emulation
1. Follow the [KServe QuickStart](https://kserve.github.io/website/latest/get_started/) to set up [Kind](https://kind.sigs.k8s.io/docs/user/quick-start) (Kubernetes in Docker) for local Kubernetes cluster emulation and install KServe on it. Make sure to check for the latest version of KServe documentation.

Now that you have a Kubernetes cluster running as a deployment target, let's move on to creating the MLflow Model to deploy.

## Using Managed MLflow on Databricks
By default, MLflow uses the local filesystem as the tracking URI. If using Databricks, set the following environment variables:

```bash
export MLFLOW_TRACKING_URI="databricks"
export DATABRICKS_HOST="https://adb-<workspace-id>.<random-number>.azuredatabricks.net"
export DATABRICKS_TOKEN="<your-access-token>"
```

## Train Model
The focus of this project is deployment. Use any ML framework and ensure your script is in the `src` folder. The model should be logged correctly by mlflow. This project uses a dummy linear regression model.

## Packaging the Model
If you use `mlflow.autolog`, it logs the model binary and dependencies automatically. The file structure should look like this:

```
model/
├── MLmodel
├── model.pkl
├── conda.yaml
├── python_env.yaml
└── requirements.txt
```

## Test Model Serving Locally
Before deployment, test the model serving locally. MLflow uses **Flask** for serving models by default, but we will use `mlserver` for compatibility with KServe. Ensure `virtualenv`, `mlserver`, and `mlserver-mlflow` are installed.

```bash
mlflow models serve -m runs:/<run_id_for_your_best_run>/model -p 1234 --enable-mlserver
```

`<run_id_for_your_best_run>/model` can point to a local directory. For simplicity, move the best run's model artifacts to the `mlflow_model` directory and reference it in the following sections.

This command starts a local server on port `1234`. To test it, send a request using `curl`:

### Making an Inference Request
Using `curl`:
```bash
curl -X POST "http://127.0.0.1:1234/invocations" \
     -H "Content-Type: application/json" \
     -d '{"inputs": [[0.5, -1.2, 3.3, 0.7, -0.8]]}'
```

Using Python:
```python
import requests
import json

url = "http://127.0.0.1:1234/invocations"
headers = {"Content-Type": "application/json"}
data = {"inputs": [[0.5, -1.2, 3.3, 0.7, -0.8]]}

response = requests.post(url, headers=headers, data=json.dumps(data))
print(response.json())
```

## Deploying Model to KServe
### Create Namespace
Create a test namespace for deploying KServe resources:

```bash
kubectl create namespace mlflow-kserve-test
```

### Build a Docker Image
According to my experience, `mlflow models build-docker` is unreliable because it creates incomplete Docker images and doesn’t expose ports correctly. Therefore, we use a custom `DockerFile` instead.

**Note**: make sure you moved the best run's model artifacts to the `mlflow_model` directory.

#### DockerFile Explanation:
- Installs `mlserver` and `mlserver-mlflow`.
- Copies the MLflow model from `mlflow_model/` to `/opt/ml/model`.
- Installs Python dependencies from `requirements.txt`.
- Creates `model-settings.json` to configure MLServer.
- Exposes port `8080` for external access.

### Build Docker Image
```bash
docker build -t mlflow-dummy .
```

### Tag and Push Docker Image
The Docker image must be stored in a registry, either public or private by granting the right priviledges to be accessible by KServe. The image should be tagged properly using the `registry_name` before getting pushed to the registry. 
```bash
docker tag mlflow-dummy <registry_name>/mlflow-dummy:latest

docker push <registry_name>/mlflow-dummy:latest
```

## Deploy Inference Service
Apply the inference service YAML configuration. The `kubectl apply -f InferenceService` command creates or updates the KServe InferenceService resource in your Kubernetes cluster, deploying the model as a scalable service.
```bash
kubectl apply -f inferenceservice.yaml
```
Expected output:
```bash
inferenceservice.serving.kserve.io/mlflow-dummy created
```

Check deployment status:
```bash
kubectl get inferenceservice -n mlflow-kserve-test
```
Expected output:
```bash
NAME           URL                                                  READY   PREV   LATEST   PREVROLLEDOUTREVISION   LATESTREADYREVISION            AGE
mlflow-dummy   http://mlflow-dummy.mlflow-kserve-test.example.com   True           100                              mlflow-dummy-predictor-00001   23h
```

## Testing the Deployment
### Kubernetes Cluster
Assuming your cluster is exposed via LoadBalancer, follow these instructions to find the Ingress IP and port. Then send a test request using curl command:
```bash
SERVICE_HOSTNAME=$(kubectl get inferenceservice mlflow-dummy -n mlflow-kserve-test -o jsonpath='{.status.url}' | cut -d "/" -f 3)
$ curl -v \
  -H "Host: ${SERVICE_HOSTNAME}" \
  -H "Content-Type: application/json" \
  -d @./test-input.json \
  http://${INGRESS_HOST}:${INGRESS_PORT}/v2/models/mlflow-dummy/infer
```
### Local Cluster
Use port forwarding to access the service locally:
```bash
INGRESS_GATEWAY_SERVICE=$(kubectl get svc -n istio-system --selector="app=istio-ingressgateway" -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward -n istio-system svc/${INGRESS_GATEWAY_SERVICE} 8080:80
```

Then, in another terminal, navigate to the project root directory and run the command below.
```bash
SERVICE_HOSTNAME=$(kubectl get inferenceservice mlflow-dummy -n mlflow-kserve-test -o jsonpath='{.status.url}' | cut -d "/" -f 3)
curl -v  \
-H "Host: ${SERVICE_HOSTNAME}" \
-H "Content-Type: application/json" http://127.0.0.1:8080/v2/models/mlflow-dummy/infer \
-d @test-input.json 
```

### Expected Output Format
```json
{
  "model_name": "mlflow-dummy",
  "id": "65026f85-054f-41a7-9acd-b2866135765b",
  "parameters": {"content_type": "np"},
  "outputs": [
    {
      "name": "output-1",
      "shape": [1,1],
      "datatype": "FP64",
      "parameters": {"content_type": "np"},
      "data": ["<the predictions>"]
    }
  ]
}
```

Your MLflow model is now deployed and ready for inference via KServe! 🚀

