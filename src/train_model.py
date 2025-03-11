import mlflow
import mlflow.sklearn
from sklearn.datasets import make_regression
from sklearn.linear_model import LinearRegression
from sklearn.model_selection import train_test_split

# Generate dummy regression data
X, y = make_regression(n_samples=100, n_features=5, noise=0.1, random_state=42)
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)


# mlflow.set_experiment("/Shared/dummy_regressor")
mlflow.set_experiment("dummy-regressor") 
mlflow.autolog()

# Start an MLflow run
with mlflow.start_run() as run:
    # Train a simple linear regression model
    model = LinearRegression()
    model.fit(X_train, y_train)
    
    # Make predictions
    predictions = model.predict(X_test)
