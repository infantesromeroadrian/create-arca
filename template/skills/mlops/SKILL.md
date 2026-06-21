---
name: mlops
description: MLOps practices for ML lifecycle management including experiment tracking, model registry, feature stores, monitoring, drift detection, and automated retraining. Use when operationalizing ML models, setting up ML infrastructure, or debugging production ML issues.
paths:
  - "**/mlflow*"
  - "**/dvc*"
  - "**/pipeline*"
  - "**/deploy*"
  - "**/serve*"
  - "**/monitor*"
---

# MLOps Best Practices 2025

## Principio Fundamental

```
"Whoever owns the data pipeline will own the production pipeline for machine learning."
— Chip Huyen
```

---

## MLOps Maturity Levels

| Level | Nombre | Características | Tools |
|-------|--------|-----------------|-------|
| 0 | No MLOps | Notebooks a prod, manual | Jupyter |
| 1 | DevOps sin MLOps | CI/CD código, no modelos | Git, GitHub Actions |
| 2 | Automated Training | Pipelines entrenamiento | MLflow, DVC |
| 3 | Automated Deployment | CI/CD para modelos | MLflow Registry, BentoML |
| 4 | Full MLOps | Monitoring, retraining auto | Evidently, Kubeflow |

---

## Stack MLOps 2025

```
┌──────────────────────────────────────────────────────────────┐
│                    MLOps Stack 2025                          │
├──────────────────────────────────────────────────────────────┤
│ Orchestration     │ Prefect, Airflow, Kubeflow Pipelines 1.7│
│ Experiment Track  │ MLflow 2.14+, W&B, Neptune              │
│ Feature Store     │ Feast 0.40+, Hopsworks, Tecton          │
│ Model Registry    │ MLflow, SageMaker, Vertex AI            │
│ Serving           │ BentoML 1.3+, TorchServe, Triton        │
│ Monitoring        │ Evidently 0.5+, WhyLabs, Arize          │
│ Data Versioning   │ DVC 3.x, LakeFS, Delta Lake             │
│ LLMOps            │ LangSmith, Weights & Biases Prompts     │
└──────────────────────────────────────────────────────────────┘
```

### Por Escala de Empresa
| Escala | Stack Recomendado |
|--------|-------------------|
| Startup/POC | MLflow + DVC + GitHub Actions + BentoML |
| Mid-size | Kubeflow + Feast + Evidently + KServe |
| Enterprise | SageMaker/Vertex AI + Custom Feature Store |

---

## Experiment Tracking

### MLflow 2.14+ (2025)
```python
import mlflow
from mlflow.models import infer_signature

# Configurar tracking
mlflow.set_tracking_uri("http://localhost:5000")  # o "mlruns" local
mlflow.set_experiment("churn-prediction-v2")

# Autolog (automático para sklearn, pytorch, etc.)
mlflow.autolog()

# O log manual con más control
with mlflow.start_run(run_name="baseline-rf"):
    # Parámetros
    mlflow.log_params({
        "model_type": "RandomForest",
        "n_estimators": 100,
        "max_depth": 10,
        "random_state": 42,
    })
    
    # Entrenar
    model.fit(X_train, y_train)
    
    # Métricas
    train_acc = model.score(X_train, y_train)
    test_acc = model.score(X_test, y_test)
    
    mlflow.log_metrics({
        "train_accuracy": train_acc,
        "test_accuracy": test_acc,
        "overfit_gap": train_acc - test_acc,
    })
    
    # Modelo con signature (recomendado 2025)
    signature = infer_signature(X_train, model.predict(X_train))
    mlflow.sklearn.log_model(
        model, 
        "model",
        signature=signature,
        input_example=X_train[:5],
    )
    
    # Artifacts
    mlflow.log_artifact("configs/model_config.yaml")
    mlflow.log_artifact("reports/confusion_matrix.png")
```

### Weights & Biases
```python
import wandb

# Inicializar
wandb.init(
    project="my-project",
    name="experiment-1",
    config={
        "learning_rate": 1e-4,
        "architecture": "ResNet50",
        "epochs": 100,
    }
)

# Log durante training
for epoch in range(num_epochs):
    wandb.log({
        "epoch": epoch,
        "train_loss": train_loss,
        "val_loss": val_loss,
        "val_accuracy": val_acc,
    })

# Log modelo
wandb.save("model.pth")

# Finalizar
wandb.finish()
```

---

## Model Registry

### MLflow Model Registry
```python
from mlflow import MlflowClient

client = MlflowClient()

# 1. Registrar modelo desde run
run_id = "abc123..."
model_uri = f"runs:/{run_id}/model"

# Registrar (crea si no existe)
model_version = mlflow.register_model(
    model_uri=model_uri,
    name="churn-predictor"
)

# 2. Agregar metadata
client.set_model_version_tag(
    name="churn-predictor",
    version=model_version.version,
    key="trained_by",
    value="pipeline-v2"
)

client.set_model_version_tag(
    name="churn-predictor",
    version=model_version.version,
    key="dataset_version",
    value="v2.3.1"
)

# 3. Transicionar a Production
client.transition_model_version_stage(
    name="churn-predictor",
    version=model_version.version,
    stage="Production"
)

# 4. Cargar modelo en producción
model = mlflow.pyfunc.load_model("models:/churn-predictor/Production")
predictions = model.predict(new_data)
```

### Model Registry Best Practices
```python
# SIEMPRE incluir metadata completa
metadata = {
    "trained_by": "pipeline-v2",
    "dataset_version": "v2.3.1",
    "git_commit": "abc123",
    "training_date": "2025-01-19",
    "metrics": {
        "accuracy": 0.95,
        "f1": 0.93,
        "latency_p99_ms": 45
    }
}

# Documentar modelo
client.update_registered_model(
    name="churn-predictor",
    description="""
    Customer churn prediction model.
    - Input: Customer features (age, tenure, usage)
    - Output: Probability of churn [0, 1]
    - Trained on 2024 Q4 data
    - Threshold: 0.5 for binary decision
    """
)
```

---

## Data Versioning con DVC 3.x

### Setup
```bash
# Inicializar
dvc init
dvc remote add -d storage s3://my-bucket/dvc-store

# Trackear datos
dvc add data/training_data.parquet
git add data/training_data.parquet.dvc data/.gitignore
git commit -m "Add training data v1"
dvc push
```

### Pipeline DVC
```yaml
# dvc.yaml
stages:
  preprocess:
    cmd: python src/preprocess.py
    deps:
      - src/preprocess.py
      - data/raw/
    params:
      - preprocess.test_size
      - preprocess.random_state
    outs:
      - data/processed/

  train:
    cmd: python src/train.py
    deps:
      - src/train.py
      - data/processed/
    params:
      - train.n_estimators
      - train.max_depth
    outs:
      - models/model.pkl
    metrics:
      - metrics.json:
          cache: false
    plots:
      - plots/confusion_matrix.png:
          cache: false

  evaluate:
    cmd: python src/evaluate.py
    deps:
      - src/evaluate.py
      - models/model.pkl
      - data/processed/test.parquet
    metrics:
      - evaluation/metrics.json:
          cache: false
```

### Ejecutar y Versionar
```bash
# Ejecutar pipeline
dvc repro

# Ver métricas
dvc metrics show

# Comparar experimentos
dvc exp show

# Volver a versión anterior
git checkout v1.0 data/training_data.parquet.dvc
dvc checkout
```

---

## Feature Store con Feast 0.40+

### Definición de Features
```python
# features/customer_features.py
from feast import Entity, Feature, FeatureView, FileSource
from feast.types import Float32, Int64
from datetime import timedelta

# Entidad
customer = Entity(
    name="customer_id",
    join_keys=["customer_id"],
    description="Customer identifier"
)

# Fuente de datos
customer_source = FileSource(
    path="data/customer_features.parquet",
    timestamp_field="event_timestamp",
)

# Feature View
customer_features = FeatureView(
    name="customer_features",
    entities=[customer],
    ttl=timedelta(days=1),
    schema=[
        Feature(name="total_purchases", dtype=Float32),
        Feature(name="avg_order_value", dtype=Float32),
        Feature(name="days_since_last_order", dtype=Int64),
        Feature(name="total_spent", dtype=Float32),
    ],
    online=True,
    source=customer_source,
    tags={"team": "ml-platform"},
)
```

### Uso en Training y Serving
```python
from feast import FeatureStore

store = FeatureStore(repo_path=".")

# Training: Point-in-time correct features
training_df = store.get_historical_features(
    entity_df=entity_df,  # customer_id + event_timestamp
    features=[
        "customer_features:total_purchases",
        "customer_features:avg_order_value",
        "customer_features:days_since_last_order",
    ],
).to_df()

# Serving: Online features (baja latencia)
online_features = store.get_online_features(
    features=[
        "customer_features:total_purchases",
        "customer_features:avg_order_value",
    ],
    entity_rows=[{"customer_id": 12345}],
).to_dict()
```

### Beneficios Feature Store
```
[PASS] Training-Serving Consistency: Mismas transformaciones
[PASS] Point-in-time Correctness: Evita data leakage temporal
[PASS] Feature Reuse: Comparte features entre equipos
[PASS] Feature Discovery: Catálogo centralizado
[PASS] Backfill: Recalcular features históricas
```

---

## Model Serving con BentoML 1.3+

### Servicio Básico
```python
# service.py
import bentoml
import numpy as np

@bentoml.service(
    resources={"cpu": "2", "memory": "4Gi"},
    traffic={"timeout": 60},
)
class ChurnPredictor:
    def __init__(self):
        # Cargar modelo desde MLflow
        import mlflow
        self.model = mlflow.pyfunc.load_model("models:/churn-predictor/Production")
    
    @bentoml.api
    def predict(self, features: np.ndarray) -> np.ndarray:
        """Predict churn probability."""
        return self.model.predict(features)
    
    @bentoml.api(batchable=True)  # Batching automático
    def predict_batch(self, features_list: list[np.ndarray]) -> list[np.ndarray]:
        """Batch prediction with adaptive batching."""
        return [self.model.predict(f) for f in features_list]
```

### Ejecutar y Deployar
```bash
# Desarrollo local
bentoml serve service.py:ChurnPredictor

# Build Bento (empaqueta todo)
bentoml build

# Containerizar
bentoml containerize churn_predictor:latest

# Deploy a BentoCloud o Kubernetes
bentoml deploy churn_predictor:latest
```

### Servicio con Validación
```python
from pydantic import BaseModel
import bentoml

class CustomerFeatures(BaseModel):
    age: int
    tenure_months: int
    monthly_charges: float
    total_charges: float

class PredictionResponse(BaseModel):
    churn_probability: float
    will_churn: bool

@bentoml.service
class ChurnPredictor:
    @bentoml.api
    def predict(self, customer: CustomerFeatures) -> PredictionResponse:
        features = np.array([[
            customer.age,
            customer.tenure_months,
            customer.monthly_charges,
            customer.total_charges
        ]])
        prob = self.model.predict_proba(features)[0, 1]
        return PredictionResponse(
            churn_probability=prob,
            will_churn=prob > 0.5
        )
```

---

## Monitoring con Evidently 0.5+ (2025)

### API Nueva - Reports
```python
from evidently import Report
from evidently.metric_preset import DataDriftPreset, DataQualityPreset

# Crear report con presets
report = Report(metrics=[
    DataDriftPreset(),
    DataQualityPreset(),
])

# Ejecutar comparación
report.run(
    reference_data=training_data,
    current_data=production_data,
)

# Guardar HTML
report.save_html("reports/drift_report.html")

# Obtener como dict (para logging)
results = report.as_dict()
drift_detected = results["metrics"][0]["result"]["dataset_drift"]
```

### Test Suite para CI/CD
```python
from evidently import TestSuite
from evidently.tests import (
    TestNumberOfColumnsWithMissingValues,
    TestNumberOfRowsWithMissingValues,
    TestShareOfDriftedColumns,
    TestColumnValueMin,
    TestColumnValueMax,
)

# Definir tests
tests = TestSuite(tests=[
    TestNumberOfColumnsWithMissingValues(eq=0),
    TestNumberOfRowsWithMissingValues(lte=0.05),  # Max 5% missing
    TestShareOfDriftedColumns(lte=0.3),  # Max 30% drifted
    TestColumnValueMin(column_name="age", gte=0),
    TestColumnValueMax(column_name="age", lte=120),
])

# Ejecutar
tests.run(reference_data=reference, current_data=current)

# Para CI/CD - falla si no pasan
if not tests.as_dict()["summary"]["all_passed"]:
    raise ValueError("Data quality tests failed!")
```

### Monitoring Continuo
```python
from evidently import Report
from evidently.metric_preset import DataDriftPreset
import schedule
import time

def check_drift():
    """Ejecutar cada hora."""
    # Obtener datos recientes
    current_data = get_last_hour_predictions()
    
    report = Report(metrics=[DataDriftPreset()])
    report.run(reference_data=training_data, current_data=current_data)
    
    results = report.as_dict()
    if results["metrics"][0]["result"]["dataset_drift"]:
        send_alert("Drift detected!")
        trigger_retraining()
    
    # Log métricas
    log_to_prometheus(results)

# Programar
schedule.every(1).hour.do(check_drift)

while True:
    schedule.run_pending()
    time.sleep(60)
```

### Tipos de Drift
| Tipo | Qué Detecta | Métrica | Threshold Típico |
|------|-------------|---------|------------------|
| Data Drift | Input distribution shift | PSI, KS-test | PSI > 0.2 |
| Concept Drift | Relación X→Y cambia | Model accuracy drop | > 5% drop |
| Prediction Drift | Output distribution shift | PSI en predictions | PSI > 0.1 |
| Label Drift | Target distribution shift | Chi-squared | p < 0.05 |

---

## CI/CD para ML

### GitHub Actions Pipeline
```yaml
# .github/workflows/ml-pipeline.yml
name: ML Pipeline

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  schedule:
    - cron: '0 0 * * 0'  # Weekly retrain

jobs:
  data-validation:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      
      - name: Install dependencies
        run: |
          pip install -r requirements.txt
          dvc pull
      
      - name: Validate data quality
        run: python scripts/validate_data.py

  train:
    needs: data-validation
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Train model
        run: |
          dvc repro
          python scripts/train.py
      
      - name: Run quality gates
        run: python scripts/quality_gates.py
      
      - name: Register model
        if: github.ref == 'refs/heads/main'
        env:
          MLFLOW_TRACKING_URI: ${{ secrets.MLFLOW_URI }}
        run: python scripts/register_model.py

  deploy:
    needs: train
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to staging
        run: |
          bentoml build
          bentoml containerize my_model:latest
          kubectl apply -f k8s/staging/
      
      - name: Run smoke tests
        run: python scripts/smoke_tests.py
      
      - name: Deploy to production
        run: kubectl apply -f k8s/production/
```

### Quality Gates
```python
# scripts/quality_gates.py
import mlflow
import json

def validate_model():
    """Quality gates antes de deploy."""
    # Cargar métricas
    with open("metrics.json") as f:
        metrics = json.load(f)
    
    # Cargar baseline (modelo en producción)
    try:
        prod_model = mlflow.pyfunc.load_model("models:/my-model/Production")
        prod_metrics = get_production_metrics()
    except:
        prod_metrics = {"accuracy": 0}  # Primer deploy
    
    # Gates
    gates = {
        "min_accuracy": metrics["accuracy"] >= 0.90,
        "beats_production": metrics["accuracy"] >= prod_metrics["accuracy"] * 0.98,
        "latency_ok": metrics.get("latency_p99_ms", 0) <= 100,
        "model_size_ok": metrics.get("model_size_mb", 0) <= 500,
        "no_data_drift": not metrics.get("data_drift_detected", False),
    }
    
    # Evaluar
    failed = [k for k, v in gates.items() if not v]
    
    if failed:
        print(f"[FAIL] Quality gates failed: {failed}")
        raise SystemExit(1)
    
    print("[PASS] All quality gates passed")

if __name__ == "__main__":
    validate_model()
```

---

## Deployment Patterns

### Canary Deployment
```python
# k8s/canary-deployment.yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: churn-predictor
spec:
  predictor:
    # 90% al modelo estable
    canaryTrafficPercent: 10
    model:
      modelFormat:
        name: mlflow
      storageUri: "s3://models/churn-predictor/v2"
```

### A/B Testing
```python
def get_prediction(request):
    """A/B testing entre modelos."""
    user_id = request.user_id
    
    # Hash determinístico para consistencia
    bucket = hash(user_id) % 100
    
    if bucket < 10:  # 10% challenger
        model = load_model("models:/challenger/Production")
        variant = "challenger"
    else:  # 90% champion
        model = load_model("models:/champion/Production")
        variant = "champion"
    
    prediction = model.predict(request.features)
    
    # Log para análisis
    log_experiment({
        "user_id": user_id,
        "variant": variant,
        "prediction": prediction,
        "timestamp": datetime.now()
    })
    
    return prediction
```

### Shadow Mode
```python
import asyncio

async def predict_with_shadow(request):
    """Modelo nuevo en paralelo sin afectar usuarios."""
    
    # Producción (respuesta al usuario)
    prod_prediction = await production_model.predict(request)
    
    # Shadow (async, no bloquea, no afecta usuario)
    asyncio.create_task(
        shadow_evaluate(request, prod_prediction)
    )
    
    return prod_prediction

async def shadow_evaluate(request, prod_prediction):
    """Evaluar modelo shadow sin afectar latencia."""
    try:
        shadow_prediction = await shadow_model.predict(request)
        
        # Log para comparación offline
        log_shadow_comparison({
            "request": request,
            "prod_prediction": prod_prediction,
            "shadow_prediction": shadow_prediction,
            "timestamp": datetime.now()
        })
    except Exception as e:
        log_error(f"Shadow model error: {e}")
```

---

## Automated Retraining

### Triggers
```yaml
# config/retraining_config.yaml
triggers:
  scheduled:
    enabled: true
    cron: "0 0 * * 0"  # Weekly
  
  performance:
    enabled: true
    metric: "accuracy"
    threshold: 0.90
    window: "7d"
  
  drift:
    enabled: true
    type: "data_drift"
    psi_threshold: 0.2
  
  data_volume:
    enabled: true
    new_samples: 10000

notification:
  slack_channel: "#ml-alerts"
  email: "ml-team@company.com"
```

### Pipeline Airflow
```python
from airflow import DAG
from airflow.operators.python import PythonOperator, BranchPythonOperator
from datetime import datetime, timedelta

def check_retraining_needed(**context):
    """Verificar si necesita reentrenamiento."""
    # Check drift
    drift_score = calculate_drift()
    if drift_score > 0.2:
        return "retrain_model"
    
    # Check performance
    current_accuracy = get_model_accuracy()
    if current_accuracy < 0.90:
        return "retrain_model"
    
    return "skip_retraining"

def retrain_model(**context):
    """Reentrenar con datos nuevos."""
    # Obtener datos
    data = get_training_data()
    
    # Entrenar
    with mlflow.start_run():
        model = train_model(data)
        metrics = evaluate_model(model)
        mlflow.log_metrics(metrics)
        mlflow.sklearn.log_model(model, "model")
    
    return metrics

def evaluate_and_promote(**context):
    """Promover si mejora."""
    new_metrics = context['task_instance'].xcom_pull(task_ids='retrain_model')
    prod_metrics = get_production_metrics()
    
    if new_metrics["accuracy"] > prod_metrics["accuracy"]:
        promote_to_production()
        return "deploy_model"
    return "skip_deployment"

with DAG(
    "ml_retraining_pipeline",
    default_args={"retries": 1},
    schedule_interval="@daily",
    start_date=datetime(2025, 1, 1),
    catchup=False,
) as dag:
    
    check = BranchPythonOperator(
        task_id="check_retraining_needed",
        python_callable=check_retraining_needed,
    )
    
    retrain = PythonOperator(
        task_id="retrain_model",
        python_callable=retrain_model,
    )
    
    skip = PythonOperator(
        task_id="skip_retraining",
        python_callable=lambda: print("No retraining needed"),
    )
    
    evaluate = BranchPythonOperator(
        task_id="evaluate_and_promote",
        python_callable=evaluate_and_promote,
    )
    
    check >> [retrain, skip]
    retrain >> evaluate
```

---

## Checklist MLOps

### Level 1 - Básico
```
□ Código versionado en Git
□ Experiment tracking (MLflow/W&B)
□ Tests unitarios para código ML
□ Documentación básica de modelos
```

### Level 2 - Intermedio
```
□ Model registry implementado
□ Data versioning (DVC)
□ CI pipeline para training
□ Reproducibilidad garantizada
□ Métricas logueadas automáticamente
```

### Level 3 - Avanzado
```
□ CD pipeline para deployment
□ Model serving con BentoML/KServe
□ Monitoring con Evidently
□ Alertas configuradas
□ A/B testing capability
```

### Level 4 - Excelencia
```
□ Feature store operativo
□ Retraining automatizado
□ Shadow deployments
□ Canary releases
□ Lineage tracking completo
□ Cost tracking por modelo
□ Governance y compliance
```

---

## Tools Quick Reference

| Función | Open Source | Managed |
|---------|-------------|---------|
| Experiment Tracking | MLflow, W&B (free tier) | W&B, Neptune |
| Model Registry | MLflow | SageMaker, Vertex AI |
| Data Versioning | DVC, LakeFS | Pachyderm |
| Feature Store | Feast | Tecton, Hopsworks |
| Orchestration | Prefect, Airflow | Kubeflow |
| Serving | BentoML, TorchServe | SageMaker Endpoints |
| Monitoring | Evidently | Arize, WhyLabs |
| LLMOps | LangSmith (free tier) | LangSmith Teams |
