---
name: model-interpretability
description: Complete guide for ML model interpretability including SHAP, LIME, attention visualization, feature importance, counterfactual explanations, and fairness auditing. Use when explaining model predictions, debugging models, or meeting regulatory requirements.
---

# Model Interpretability & Explainability

## Stack 2025

| Component | Tools |
|-----------|-------|
| Feature Attribution | SHAP, LIME, Captum |
| Visualization | interpret, eli5, ecco |
| Fairness | Fairlearn, AIF360, Aequitas |
| Model Cards | model-card-toolkit |
| LLM Explainability | LangSmith, attention analysis |

---

## Interpretability Taxonomy

| Method | Scope | Model Agnostic | Use Case |
|--------|-------|----------------|----------|
| SHAP | Global/Local | Yes | Feature attribution |
| LIME | Local | Yes | Instance explanation |
| Attention | Local | No (Transformers) | Token importance |
| Permutation | Global | Yes | Feature importance |
| Counterfactual | Local | Yes | "What-if" analysis |

---

## SHAP (SHapley Additive exPlanations)

### TreeSHAP (Fast for Tree Models)

```python
import shap
import xgboost as xgb

# Train model
model = xgb.XGBClassifier()
model.fit(X_train, y_train)

# Create explainer
explainer = shap.TreeExplainer(model)

# Compute SHAP values
shap_values = explainer.shap_values(X_test)
# For binary classification: shape (n_samples, n_features)
# For multiclass: list of arrays per class

# Single prediction explanation
shap.force_plot(
    explainer.expected_value,
    shap_values[0],
    X_test.iloc[0],
    feature_names=feature_names,
)

# Summary plot (global importance)
shap.summary_plot(shap_values, X_test, feature_names=feature_names)

# Dependence plot (feature interaction)
shap.dependence_plot("feature_name", shap_values, X_test)

# Bar plot (mean absolute SHAP)
shap.plots.bar(shap_values)
```

### KernelSHAP (Model Agnostic)

```python
# For any model (slower)
explainer = shap.KernelExplainer(model.predict_proba, shap.sample(X_train, 100))

# Compute for subset (expensive)
shap_values = explainer.shap_values(X_test[:100])
```

### DeepSHAP (Neural Networks)

```python
import torch
import shap

# PyTorch model
model.eval()

# Background data (representative sample)
background = X_train[:100]

# Create explainer
explainer = shap.DeepExplainer(model, torch.tensor(background).float())

# Compute SHAP values
shap_values = explainer.shap_values(torch.tensor(X_test[:50]).float())

# Visualize
shap.image_plot(shap_values, X_test[:50])  # For images
```

### SHAP for Text (Transformers)

```python
from transformers import pipeline
import shap

# Load model
classifier = pipeline("sentiment-analysis", model="distilbert-base-uncased")

# Create explainer
explainer = shap.Explainer(classifier)

# Explain
shap_values = explainer(["This movie was absolutely fantastic!"])

# Visualize token importance
shap.plots.text(shap_values)
```

---

## LIME (Local Interpretable Model-agnostic Explanations)

### Tabular Data

```python
from lime.lime_tabular import LimeTabularExplainer
import numpy as np

# Create explainer
explainer = LimeTabularExplainer(
    X_train.values,
    feature_names=feature_names,
    class_names=class_names,
    mode="classification",
    discretize_continuous=True,
)

# Explain single prediction
explanation = explainer.explain_instance(
    X_test.iloc[0].values,
    model.predict_proba,
    num_features=10,
    num_samples=5000,
)

# Visualize
explanation.show_in_notebook()
explanation.as_pyplot_figure()

# Get feature weights
feature_weights = explanation.as_list()
# [('feature_1 > 0.5', 0.23), ('feature_2 <= 0.3', -0.15), ...]
```

### Text Data

```python
from lime.lime_text import LimeTextExplainer

explainer = LimeTextExplainer(class_names=["negative", "positive"])

def predict_fn(texts):
    """Wrapper for model prediction."""
    return model.predict_proba(vectorizer.transform(texts))

explanation = explainer.explain_instance(
    "This product is amazing and works great!",
    predict_fn,
    num_features=10,
)

explanation.show_in_notebook()
```

### Image Data

```python
from lime import lime_image
from skimage.segmentation import slic

explainer = lime_image.LimeImageExplainer()

def predict_fn(images):
    """Preprocess and predict."""
    images = preprocess(images)
    return model.predict(images)

explanation = explainer.explain_instance(
    image,
    predict_fn,
    top_labels=3,
    hide_color=0,
    num_samples=1000,
    segmentation_fn=lambda x: slic(x, n_segments=50),
)

# Visualize
temp, mask = explanation.get_image_and_mask(
    label=explanation.top_labels[0],
    positive_only=True,
    num_features=5,
    hide_rest=False,
)
plt.imshow(mark_boundaries(temp, mask))
```

---

## Captum (PyTorch)

### Integrated Gradients

```python
from captum.attr import IntegratedGradients, LayerIntegratedGradients
from captum.attr import visualization as viz
import torch

model.eval()

# Create attributor
ig = IntegratedGradients(model)

# Compute attributions
input_tensor = torch.tensor(X_test[0:1]).float().requires_grad_(True)
baseline = torch.zeros_like(input_tensor)

attributions = ig.attribute(
    input_tensor,
    baselines=baseline,
    target=predicted_class,
    n_steps=50,
)

# Visualize for images
viz.visualize_image_attr(
    attributions[0].permute(1, 2, 0).detach().numpy(),
    original_image,
    method="heat_map",
    sign="positive",
)
```

### Layer Attribution (for CNNs)

```python
from captum.attr import LayerGradCam, LayerAttribution

# GradCAM for CNNs
layer_gc = LayerGradCam(model, model.layer4[-1])  # Last conv layer

attributions = layer_gc.attribute(input_tensor, target=predicted_class)

# Upsample to input size
upsampled = LayerAttribution.interpolate(attributions, input_tensor.shape[2:])

viz.visualize_image_attr(
    upsampled[0].permute(1, 2, 0).detach().numpy(),
    original_image,
    method="blended_heat_map",
    sign="positive",
)
```

### Text Attribution

```python
from captum.attr import LayerIntegratedGradients
from transformers import AutoModelForSequenceClassification, AutoTokenizer

model = AutoModelForSequenceClassification.from_pretrained("bert-base-uncased")
tokenizer = AutoTokenizer.from_pretrained("bert-base-uncased")

def forward_func(inputs, attention_mask):
    return model(inputs, attention_mask=attention_mask).logits

# Attribute to embeddings
lig = LayerIntegratedGradients(forward_func, model.bert.embeddings)

inputs = tokenizer("This movie was great!", return_tensors="pt")
attributions = lig.attribute(
    inputs["input_ids"],
    additional_forward_args=(inputs["attention_mask"],),
    target=1,  # Positive class
)

# Sum attributions per token
token_attributions = attributions.sum(dim=-1).squeeze()
tokens = tokenizer.convert_ids_to_tokens(inputs["input_ids"][0])

for token, attr in zip(tokens, token_attributions):
    print(f"{token}: {attr:.4f}")
```

---

## Attention Visualization

### Transformer Attention

```python
from transformers import AutoModel, AutoTokenizer
import torch
import matplotlib.pyplot as plt
import seaborn as sns

model = AutoModel.from_pretrained("bert-base-uncased", output_attentions=True)
tokenizer = AutoTokenizer.from_pretrained("bert-base-uncased")

inputs = tokenizer("The cat sat on the mat", return_tensors="pt")

with torch.no_grad():
    outputs = model(**inputs)

# outputs.attentions: tuple of (batch, heads, seq_len, seq_len) per layer
attention = outputs.attentions[-1]  # Last layer
attention = attention.squeeze().mean(dim=0)  # Average across heads

tokens = tokenizer.convert_ids_to_tokens(inputs["input_ids"][0])

# Plot heatmap
plt.figure(figsize=(10, 8))
sns.heatmap(
    attention.numpy(),
    xticklabels=tokens,
    yticklabels=tokens,
    cmap="Blues",
)
plt.title("Attention Weights")
plt.show()
```

### BertViz (Interactive)

```python
from bertviz import head_view, model_view
from transformers import AutoModel, AutoTokenizer

model = AutoModel.from_pretrained("bert-base-uncased", output_attentions=True)
tokenizer = AutoTokenizer.from_pretrained("bert-base-uncased")

inputs = tokenizer("The cat sat on the mat", return_tensors="pt")
outputs = model(**inputs)

tokens = tokenizer.convert_ids_to_tokens(inputs["input_ids"][0])

# Head view (single layer attention patterns)
head_view(outputs.attentions, tokens)

# Model view (all layers)
model_view(outputs.attentions, tokens)
```

---

## Feature Importance

### Permutation Importance

```python
from sklearn.inspection import permutation_importance
import matplotlib.pyplot as plt

# Compute permutation importance
result = permutation_importance(
    model,
    X_test,
    y_test,
    n_repeats=10,
    random_state=42,
    scoring="accuracy",
)

# Sort by importance
sorted_idx = result.importances_mean.argsort()[::-1]

# Plot
plt.figure(figsize=(10, 8))
plt.boxplot(
    result.importances[sorted_idx[:20]].T,
    labels=[feature_names[i] for i in sorted_idx[:20]],
    vert=False,
)
plt.title("Permutation Importance")
plt.tight_layout()
plt.show()
```

### Drop-Column Importance

```python
from sklearn.model_selection import cross_val_score
import numpy as np

def drop_column_importance(model, X, y, cv=5):
    """Compute importance by dropping each feature."""
    baseline_score = cross_val_score(model, X, y, cv=cv).mean()
    
    importances = {}
    for col in X.columns:
        X_dropped = X.drop(columns=[col])
        score = cross_val_score(model, X_dropped, y, cv=cv).mean()
        importances[col] = baseline_score - score
    
    return dict(sorted(importances.items(), key=lambda x: x[1], reverse=True))
```

---

## Counterfactual Explanations

### DiCE (Diverse Counterfactual Explanations)

```python
import dice_ml
from dice_ml import Dice

# Prepare data
data = dice_ml.Data(
    dataframe=df,
    continuous_features=["age", "income"],
    outcome_name="approved",
)

# Wrap model
model_dice = dice_ml.Model(model=model, backend="sklearn")

# Create explainer
exp = Dice(data, model_dice)

# Generate counterfactuals
query = df.iloc[0:1].drop(columns=["approved"])

counterfactuals = exp.generate_counterfactuals(
    query,
    total_CFs=5,
    desired_class="opposite",
    features_to_vary=["income", "age"],
)

counterfactuals.visualize_as_dataframe()
# Shows: "If income increased by $10k, prediction would change"
```

### What-If Analysis

```python
def what_if_analysis(model, instance, feature, values):
    """Analyze prediction changes across feature values."""
    results = []
    
    for value in values:
        modified = instance.copy()
        modified[feature] = value
        pred = model.predict_proba([modified])[0]
        results.append({"value": value, "probability": pred[1]})
    
    return pd.DataFrame(results)

# Example
analysis = what_if_analysis(
    model,
    X_test.iloc[0],
    "income",
    range(20000, 100000, 5000)
)

plt.plot(analysis["value"], analysis["probability"])
plt.xlabel("Income")
plt.ylabel("Approval Probability")
plt.title("What-If Analysis: Income vs Approval")
```

---

## Fairness Auditing

### Fairlearn

```python
from fairlearn.metrics import MetricFrame, selection_rate, demographic_parity_difference
from fairlearn.reductions import ExponentiatedGradient, DemographicParity
from sklearn.metrics import accuracy_score

# Compute metrics by group
metric_frame = MetricFrame(
    metrics={
        "accuracy": accuracy_score,
        "selection_rate": selection_rate,
    },
    y_true=y_test,
    y_pred=y_pred,
    sensitive_features=sensitive_features,  # e.g., gender, race
)

print(metric_frame.by_group)
print(f"Demographic Parity Difference: {demographic_parity_difference(y_test, y_pred, sensitive_features=sensitive_features):.3f}")

# Mitigate bias with constrained optimization
mitigator = ExponentiatedGradient(
    estimator=base_model,
    constraints=DemographicParity(),
)

mitigator.fit(X_train, y_train, sensitive_features=sensitive_train)
fair_predictions = mitigator.predict(X_test)
```

### Bias Metrics

```python
def compute_fairness_metrics(y_true, y_pred, sensitive):
    """Compute common fairness metrics."""
    groups = np.unique(sensitive)
    
    metrics = {}
    
    # Per-group metrics
    for group in groups:
        mask = sensitive == group
        metrics[f"TPR_{group}"] = np.mean(y_pred[mask & (y_true == 1)] == 1)
        metrics[f"FPR_{group}"] = np.mean(y_pred[mask & (y_true == 0)] == 1)
        metrics[f"selection_rate_{group}"] = np.mean(y_pred[mask])
    
    # Parity metrics
    metrics["demographic_parity_diff"] = abs(
        metrics[f"selection_rate_{groups[0]}"] - 
        metrics[f"selection_rate_{groups[1]}"]
    )
    
    metrics["equalized_odds_diff"] = max(
        abs(metrics[f"TPR_{groups[0]}"] - metrics[f"TPR_{groups[1]}"]),
        abs(metrics[f"FPR_{groups[0]}"] - metrics[f"FPR_{groups[1]}"])
    )
    
    return metrics
```

---

## Model Cards

```python
from model_card_toolkit import ModelCardToolkit
import model_card_toolkit as mct

# Initialize toolkit
toolkit = ModelCardToolkit()

# Create model card
model_card = toolkit.scaffold_assets()

# Fill in details
model_card.model_details.name = "Loan Approval Model"
model_card.model_details.version.name = "v1.0"
model_card.model_details.owners = [
    mct.Owner(name="ML Team", contact="ml-team@company.com")
]

# Intended use
model_card.model_details.overview = "Predicts loan approval likelihood"
model_card.considerations.users = [
    mct.User(description="Loan officers for decision support")
]
model_card.considerations.use_cases = [
    mct.UseCase(description="Assist in loan approval decisions")
]

# Limitations
model_card.considerations.limitations = [
    mct.Limitation(description="Not validated for loans > $1M")
]

# Performance metrics
model_card.quantitative_analysis.performance_metrics = [
    mct.PerformanceMetric(type="accuracy", value="0.89"),
    mct.PerformanceMetric(type="AUC", value="0.94"),
]

# Fairness analysis
model_card.quantitative_analysis.graphics.collection = [
    mct.Graphic(name="Fairness Analysis", image=fairness_plot_base64)
]

# Export
toolkit.update_model_card(model_card)
html = toolkit.export_format()
```

---

## Production Explanations

```python
from fastapi import FastAPI
from pydantic import BaseModel
import shap
import numpy as np

app = FastAPI()

# Pre-load model and explainer
model = load_model()
explainer = shap.TreeExplainer(model)

class PredictionRequest(BaseModel):
    features: dict

class ExplanationResponse(BaseModel):
    prediction: float
    probability: float
    top_features: list
    shap_values: dict

@app.post("/predict_explain", response_model=ExplanationResponse)
def predict_with_explanation(request: PredictionRequest):
    # Prepare input
    X = pd.DataFrame([request.features])
    
    # Predict
    pred = model.predict(X)[0]
    prob = model.predict_proba(X)[0, 1]
    
    # Explain
    shap_values = explainer.shap_values(X)[0]
    
    # Top contributing features
    feature_importance = sorted(
        zip(X.columns, shap_values),
        key=lambda x: abs(x[1]),
        reverse=True
    )[:5]
    
    return ExplanationResponse(
        prediction=int(pred),
        probability=float(prob),
        top_features=[
            {"feature": f, "contribution": float(v)}
            for f, v in feature_importance
        ],
        shap_values=dict(zip(X.columns, shap_values.tolist())),
    )
```

---

## Anti-patterns

| [FAIL] Don't | [PASS] Do |
|----------|-------|
| Use SHAP on huge datasets directly | Sample background data |
| Ignore feature correlations in LIME | Use domain knowledge |
| Treat attention as explanation | Use with caution, combine methods |
| Skip fairness auditing | Audit before deployment |
| Generate explanations without validation | Sanity check explanations |
| Assume explanations are ground truth | Treat as approximations |
