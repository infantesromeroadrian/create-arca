---
name: ml-fundamentals
description: ML Engineering best practices - project structure, sklearn pipelines, OOP patterns, data leakage prevention, experiment tracking, and production-ready code. Use when building ML projects, structuring code, or implementing training pipelines.
paths:
  - "**/train*.py"
  - "**/model*.py"
  - "**/pipeline*.py"
  - "**/features*.py"
  - "**/preprocess*.py"
---

# ML Engineering Best Practices 2025

## Principio Fundamental

```
"Do machine learning like the great engineer you are,
 not like the great ML expert you aren't."
 — Google Rules of ML

"Whoever owns the data pipeline will own the production pipeline."
 — Chip Huyen
```

---

## Estructura de Proyecto (Cookiecutter Data Science v2)

### Crear Proyecto
```bash
# Instalar (recomendado con pipx)
pipx install cookiecutter-data-science

# Crear proyecto
ccds
```

### Estructura Estándar
```
my_project/
├── data/
│   ├── raw/              # Datos originales (INMUTABLES)
│   ├── interim/          # Datos intermedios transformados
│   ├── processed/        # Datos finales para modelado
│   └── external/         # Datos de terceros
├── models/               # Modelos serializados (.pkl, .pt)
├── notebooks/            # Jupyter notebooks (exploración)
│   └── 1.0-abc-initial-exploration.ipynb
├── src/my_project/       # Código fuente (módulo Python)
│   ├── __init__.py
│   ├── config.py         # Configuración y constantes
│   ├── dataset.py        # Carga y generación de datos
│   ├── features.py       # Feature engineering
│   ├── modeling/
│   │   ├── __init__.py
│   │   ├── train.py      # Entrenamiento
│   │   └── predict.py    # Inferencia
│   └── plots.py          # Visualizaciones
├── tests/                # Tests unitarios
├── pyproject.toml        # Dependencias (uv/poetry)
├── Makefile              # Comandos: make train, make data
└── README.md
```

### Reglas de Estructura
```
1. data/raw/ es INMUTABLE - nunca modificar datos originales
2. Notebooks son para exploración, NO para producción
3. Todo código reutilizable va en src/
4. Un notebook = un propósito claro (numeración: 1.0-initials-description)
5. Modelos versionados con metadatos
```

---

## El Momento del Split - CRÍTICO

### Regla de Oro
```
┌─────────────────────────────────────────────────────────────────┐
│  SIEMPRE: Split ANTES de cualquier preprocessing               │
│  NUNCA: fit_transform() en todo el dataset                     │
│  NUNCA: Feature selection antes del split                      │
└─────────────────────────────────────────────────────────────────┘
```

### Orden Correcto
```python
# 1. CARGAR datos
df = pd.read_csv("data/raw/dataset.csv")

# 2. SPLIT inmediatamente (antes de CUALQUIER transformación)
from sklearn.model_selection import train_test_split

X = df.drop("target", axis=1)
y = df["target"]

X_train, X_temp, y_train, y_temp = train_test_split(
    X, y, 
    test_size=0.3, 
    random_state=42, 
    stratify=y  # Mantener proporción de clases
)
X_val, X_test, y_val, y_test = train_test_split(
    X_temp, y_temp, 
    test_size=0.5, 
    random_state=42,
    stratify=y_temp
)

# 3. AHORA preprocessing (solo fit en train)
# Usar Pipeline para evitar errores
```

### Proporciones Recomendadas
| Dataset Size | Train | Val | Test |
|--------------|-------|-----|------|
| < 10K | 60% | 20% | 20% |
| 10K - 100K | 70% | 15% | 15% |
| > 100K | 80% | 10% | 10% |
| > 1M | 90%+ | 5% | 5% |

---

## sklearn.Pipeline - El Patrón Central

### ¿Por Qué Pipeline?
```
[PASS] Previene data leakage automáticamente
[PASS] fit() solo en train, transform() en val/test
[PASS] Serializable (joblib) para producción
[PASS] Compatible con GridSearchCV
[PASS] Código limpio y mantenible
```

### Pipeline Básico
```python
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.ensemble import RandomForestClassifier

pipeline = Pipeline([
    ('scaler', StandardScaler()),
    ('classifier', RandomForestClassifier(random_state=42))
])

# fit() aplica scaler.fit_transform + classifier.fit en train
pipeline.fit(X_train, y_train)

# score() aplica scaler.transform + classifier.predict en test
pipeline.score(X_test, y_test)
```

### ColumnTransformer - Diferentes Tipos de Columnas
```python
from sklearn.compose import ColumnTransformer
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler, OneHotEncoder
from sklearn.impute import SimpleImputer

# Identificar columnas por tipo
numeric_features = ['age', 'income', 'balance']
categorical_features = ['gender', 'country', 'occupation']

# Transformers para cada tipo
numeric_transformer = Pipeline([
    ('imputer', SimpleImputer(strategy='median')),
    ('scaler', StandardScaler())
])

categorical_transformer = Pipeline([
    ('imputer', SimpleImputer(strategy='most_frequent')),
    ('encoder', OneHotEncoder(handle_unknown='ignore', sparse_output=False))
])

# Combinar en ColumnTransformer
preprocessor = ColumnTransformer(
    transformers=[
        ('num', numeric_transformer, numeric_features),
        ('cat', categorical_transformer, categorical_features)
    ],
    remainder='drop'  # o 'passthrough' para mantener otras columnas
)

# Pipeline completo con modelo
full_pipeline = Pipeline([
    ('preprocessor', preprocessor),
    ('classifier', RandomForestClassifier(random_state=42))
])

# Una sola llamada - todo manejado correctamente
full_pipeline.fit(X_train, y_train)
predictions = full_pipeline.predict(X_test)
```

---

## Custom Transformers - POO para ML

### Patrón BaseEstimator + TransformerMixin
```python
from sklearn.base import BaseEstimator, TransformerMixin
import numpy as np

class DebtToIncomeRatio(BaseEstimator, TransformerMixin):
    """
    Custom transformer que crea feature debt_to_income.
    
    Hereda de:
    - BaseEstimator: get_params(), set_params() para GridSearch
    - TransformerMixin: fit_transform() automático
    """
    
    def __init__(self, debt_col='total_debt', income_col='annual_income'):
        # Parámetros en __init__ para GridSearch
        self.debt_col = debt_col
        self.income_col = income_col
    
    def fit(self, X, y=None):
        # Aprender parámetros del training set si es necesario
        # Ejemplo: calcular estadísticas para clipping
        self.income_median_ = X[self.income_col].median()
        return self  # SIEMPRE retornar self
    
    def transform(self, X, y=None):
        # SIEMPRE hacer copia para no mutar input
        X = X.copy()
        
        # Crear feature
        income = X[self.income_col].replace(0, self.income_median_)
        X['debt_to_income'] = X[self.debt_col] / income
        
        return X
    
    def get_feature_names_out(self, input_features=None):
        # Para compatibilidad con ColumnTransformer
        if input_features is None:
            return np.array(['debt_to_income'])
        return np.append(input_features, 'debt_to_income')
```

### Transformer para Feature Selection
```python
class VarianceThresholdSelector(BaseEstimator, TransformerMixin):
    """Elimina features con varianza menor al threshold."""
    
    def __init__(self, threshold=0.01):
        self.threshold = threshold
    
    def fit(self, X, y=None):
        # Calcular varianza en TRAINING set
        self.variances_ = np.var(X, axis=0)
        self.mask_ = self.variances_ > self.threshold
        self.selected_features_ = np.where(self.mask_)[0]
        return self
    
    def transform(self, X, y=None):
        # Aplicar máscara aprendida
        return X[:, self.mask_] if isinstance(X, np.ndarray) else X.iloc[:, self.mask_]
```

### Transformer con Logging
```python
import logging

class LoggingTransformer(BaseEstimator, TransformerMixin):
    """Wrapper que loguea shape antes/después de transformación."""
    
    def __init__(self, transformer, name="transformer"):
        self.transformer = transformer
        self.name = name
        self.logger = logging.getLogger(__name__)
    
    def fit(self, X, y=None):
        self.logger.info(f"{self.name} fitting on shape {X.shape}")
        self.transformer.fit(X, y)
        return self
    
    def transform(self, X, y=None):
        self.logger.info(f"{self.name} input shape: {X.shape}")
        X_transformed = self.transformer.transform(X)
        self.logger.info(f"{self.name} output shape: {X_transformed.shape}")
        return X_transformed
```

---

## Data Leakage - Fuentes y Prevención

### Tipos de Leakage

| Tipo | Causa | Prevención |
|------|-------|------------|
| **Train-Test Contamination** | Preprocessing antes de split | Pipeline + split primero |
| **Target Leakage** | Feature derivada del target | Revisar correlaciones sospechosas |
| **Temporal Leakage** | Usar datos futuros | TimeSeriesSplit |
| **Duplicates** | Mismo sample en train/test | Deduplicar antes de split |

### [FAIL] Código con Leakage
```python
# MALO: Feature selection en TODO el dataset
selector = SelectKBest(k=50)
X_selected = selector.fit_transform(X, y)  # ¡LEAK!
X_train, X_test = train_test_split(X_selected)

# MALO: Scaling antes de split
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)  # ¡LEAK!
X_train, X_test = train_test_split(X_scaled)

# MALO: Imputación con estadísticas globales
X['age'] = X['age'].fillna(X['age'].mean())  # ¡LEAK!
```

### [PASS] Código Correcto
```python
# Pipeline maneja todo automáticamente
pipeline = Pipeline([
    ('imputer', SimpleImputer(strategy='mean')),
    ('scaler', StandardScaler()),
    ('selector', SelectKBest(k=50)),
    ('model', RandomForestClassifier())
])

# Split PRIMERO
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2)

# Pipeline hace fit solo en train
pipeline.fit(X_train, y_train)
pipeline.score(X_test, y_test)
```

---

## Experiment Tracking

### MLflow (Recomendado)
```python
import mlflow
from mlflow.models import infer_signature

# Configurar experimento
mlflow.set_tracking_uri("http://localhost:5000")  # o "mlruns" para local
mlflow.set_experiment("churn-prediction-v2")

with mlflow.start_run(run_name="rf-baseline"):
    # Log parámetros
    mlflow.log_param("model_type", "RandomForest")
    mlflow.log_param("n_estimators", 100)
    mlflow.log_param("random_state", 42)
    mlflow.log_param("train_size", len(X_train))
    
    # Entrenar
    pipeline.fit(X_train, y_train)
    
    # Log métricas
    train_acc = pipeline.score(X_train, y_train)
    test_acc = pipeline.score(X_test, y_test)
    mlflow.log_metric("train_accuracy", train_acc)
    mlflow.log_metric("test_accuracy", test_acc)
    mlflow.log_metric("overfit_gap", train_acc - test_acc)
    
    # Log modelo con signature
    signature = infer_signature(X_train, pipeline.predict(X_train))
    mlflow.sklearn.log_model(
        pipeline, 
        "model",
        signature=signature,
        input_example=X_train.iloc[:5]
    )
    
    # Log artifacts
    mlflow.log_artifact("reports/confusion_matrix.png")
    mlflow.log_artifact("configs/model_config.yaml")
```

### Config con Hydra
```python
# configs/train.yaml
model:
  type: RandomForest
  n_estimators: 100
  max_depth: 10
  random_state: 42

data:
  path: data/processed/train.parquet
  test_size: 0.2
  
preprocessing:
  numeric_strategy: median
  categorical_strategy: most_frequent

# train.py
import hydra
from omegaconf import DictConfig

@hydra.main(config_path="configs", config_name="train", version_base=None)
def train(cfg: DictConfig):
    # cfg.model.n_estimators, cfg.data.path, etc.
    model = RandomForestClassifier(
        n_estimators=cfg.model.n_estimators,
        max_depth=cfg.model.max_depth,
        random_state=cfg.model.random_state
    )
    # ...
```

---

## Reproducibilidad

### Configurar Seeds Completo
```python
import random
import numpy as np
import os

def set_seed(seed: int = 42):
    """Configura seeds para reproducibilidad."""
    random.seed(seed)
    np.random.seed(seed)
    os.environ["PYTHONHASHSEED"] = str(seed)
    
    # PyTorch (si se usa)
    try:
        import torch
        torch.manual_seed(seed)
        if torch.cuda.is_available():
            torch.cuda.manual_seed(seed)
            torch.cuda.manual_seed_all(seed)
            torch.backends.cudnn.deterministic = True
            torch.backends.cudnn.benchmark = False
    except ImportError:
        pass
    
    # TensorFlow (si se usa)
    try:
        import tensorflow as tf
        tf.random.set_seed(seed)
    except ImportError:
        pass

# Llamar al inicio
set_seed(42)
```

### Checklist Reproducibilidad
```
□ Seeds fijos en código
□ random_state en TODOS los estimadores
□ Dependencias en pyproject.toml con versiones exactas
□ Dataset versionado (DVC, git-lfs)
□ Git commit SHA logueado
□ Config completa guardada (Hydra, YAML)
□ Dockerfile para environment
```

---

## Cross-Validation Patterns

### Selección de Strategy
| Situación | CV Strategy |
|-----------|-------------|
| Clasificación balanceada | `KFold(n_splits=5, shuffle=True)` |
| Clasificación imbalanceada | `StratifiedKFold` |
| Series temporales | `TimeSeriesSplit` |
| Datos agrupados (usuarios) | `GroupKFold` |
| Hyperparameter tuning | **Nested CV** |

### Nested CV (Sin Leak en Tuning)
```python
from sklearn.model_selection import cross_val_score, GridSearchCV, StratifiedKFold

# Inner loop: buscar mejores hyperparams
inner_cv = StratifiedKFold(n_splits=3, shuffle=True, random_state=42)

# Outer loop: evaluar modelo con mejores hyperparams
outer_cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)

# GridSearch como estimador
clf = GridSearchCV(
    estimator=RandomForestClassifier(random_state=42),
    param_grid={'n_estimators': [50, 100], 'max_depth': [5, 10]},
    cv=inner_cv,
    scoring='f1_weighted'
)

# Evaluar con outer CV
nested_scores = cross_val_score(clf, X, y, cv=outer_cv, scoring='f1_weighted')
print(f"Nested CV F1: {nested_scores.mean():.3f} ± {nested_scores.std():.3f}")
```

---

## Serialización y Deployment

### Guardar Pipeline Completo
```python
import joblib
from datetime import datetime

# Guardar
model_path = f"models/pipeline_{datetime.now():%Y%m%d_%H%M%S}.pkl"
joblib.dump(pipeline, model_path)

# Metadatos
metadata = {
    "model_path": model_path,
    "train_date": datetime.now().isoformat(),
    "train_size": len(X_train),
    "features": list(X_train.columns),
    "metrics": {"accuracy": accuracy, "f1": f1_score},
    "git_commit": os.popen("git rev-parse HEAD").read().strip()
}
joblib.dump(metadata, model_path.replace(".pkl", "_metadata.pkl"))
```

### Cargar y Predecir
```python
# Cargar
pipeline = joblib.load("models/pipeline_20250119.pkl")

# Predecir (pipeline aplica todo el preprocessing)
predictions = pipeline.predict(new_data)
probabilities = pipeline.predict_proba(new_data)
```

---

## Testing para ML

### Test de Pipeline
```python
# tests/test_pipeline.py
import pytest
import numpy as np
from src.my_project.modeling.train import create_pipeline

@pytest.fixture
def sample_data():
    """Datos sintéticos para testing."""
    np.random.seed(42)
    X = pd.DataFrame({
        'age': np.random.randint(18, 80, 100),
        'income': np.random.normal(50000, 15000, 100),
        'gender': np.random.choice(['M', 'F'], 100)
    })
    y = np.random.randint(0, 2, 100)
    return X, y

def test_pipeline_fits(sample_data):
    """Pipeline debe poder hacer fit sin errores."""
    X, y = sample_data
    pipeline = create_pipeline()
    pipeline.fit(X, y)
    assert hasattr(pipeline, 'predict')

def test_pipeline_output_shape(sample_data):
    """Predictions deben tener shape correcto."""
    X, y = sample_data
    pipeline = create_pipeline()
    pipeline.fit(X, y)
    predictions = pipeline.predict(X)
    assert predictions.shape == (len(X),)

def test_no_data_leakage(sample_data):
    """Verificar que no hay leakage."""
    X, y = sample_data
    X_train, X_test = X[:80], X[80:]
    y_train, y_test = y[:80], y[80:]
    
    pipeline = create_pipeline()
    pipeline.fit(X_train, y_train)
    
    # Scaler debe tener stats de train, no de todo
    scaler = pipeline.named_steps['preprocessor'].transformers_[0][1].named_steps['scaler']
    assert scaler.mean_ is not None  # Fitted
```

---

## Herramientas 2025

| Categoría | Herramienta | Uso |
|-----------|-------------|-----|
| **Package Manager** | uv | Gestión de dependencias |
| **ML Framework** | scikit-learn, PyTorch | Modelado |
| **Experiment Tracking** | MLflow, W&B | Logging |
| **Data Versioning** | DVC | Versionado de datos |
| **Config** | Hydra | Configuración |
| **Validation** | Deepchecks, Great Expectations | Data quality |
| **Tuning** | Optuna | Hyperparameter optimization |
| **Project Template** | Cookiecutter Data Science v2 | Estructura |

---

## Checklist ML Engineering

### Pre-Training
```
□ Estructura de proyecto (Cookiecutter)
□ Split ANTES de cualquier preprocessing
□ Pipeline construido (no scripts sueltos)
□ Custom transformers con BaseEstimator
□ Experiment tracking configurado
□ Seeds fijos
□ Tests básicos pasando
```

### Post-Training
```
□ Métricas en TEST set (no val)
□ Comparación vs baseline
□ Pipeline serializado con metadata
□ Métricas logueadas en MLflow
□ Código revisable (no notebooks)
□ Reproducible (otro run = mismas métricas)
```

### Anti-Patterns
```
[FAIL] Preprocessing antes de split
[FAIL] fit_transform() en todo el dataset
[FAIL] Código en notebooks para producción
[FAIL] Modelos sin versionado
[FAIL] random_state no especificado
[FAIL] Métricas solo en training set
[FAIL] Data en código (hardcoded paths)
```
