# Use an official Python runtime as a parent image
FROM python:3.10-slim

# Set the working directory
WORKDIR /opt/mlflow

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install MLServer
RUN pip install --no-cache-dir mlserver==1.6.1 mlserver-mlflow==1.6.1

# Copy your MLflow model into the container
COPY mlflow_model /opt/ml/model

# Install Python dependencies for the model
RUN pip install --no-cache-dir -r /opt/ml/model/requirements.txt

# Create the model-settings.json file for MLServer
RUN echo '{"name": "mlflow-dummy", "implementation": "mlserver_mlflow.MLflowRuntime", "http_port": 8080}' > /opt/ml/model/model-settings.json

# Expose the port for the model server
EXPOSE 8080

# Define the entrypoint command to run MLServer
CMD ["mlserver", "start", "/opt/ml/model"]