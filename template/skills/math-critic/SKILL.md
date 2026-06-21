---
name: math-critic
description: Mathematical rigor reference for ML/DL/LLM code. Loss function correctness, gradient verification, numerical stability patterns, statistical validity, attention math, RAG scoring. Use when auditing @ml-engineer, @dl-engineer, or @ai-engineer output before @code-critic. Includes derivations, antipatterns, and canonical references.
paths:
  - "**/train*.py"
  - "**/ml/**"
  - "**/dl/**"
  - "**/notebooks/**"
  - "**/*.ipynb"
effort: max
---

# Math Critic — Rigor Reference

## 1. Loss Function Correctness

### Classification — Cross-Entropy
Correct: `F.cross_entropy(logits, target)` — fuses `log_softmax + nll_loss`.
Antipattern: `F.nll_loss(torch.log(F.softmax(logits, dim=-1)), target)` — numerically unstable; `softmax` can underflow, then `log(0) = -inf`.

### Imbalance Handling
- Ratio < 5:1 → `class_weight='balanced'`.
- 5-20:1 → SMOTE + `class_weight`. Compute SMOTE INSIDE CV fold, never before split.
- > 20:1 → SMOTE + `class_weight` + threshold tuning. Primary metric: AUC-PR (AUC-ROC lies with extreme imbalance).

### Regression
- MSE: assumes Gaussian errors. Check residuals.
- MAE: assumes Laplacian errors. Robust to outliers.
- Huber: adaptive, delta-parameterized.
- Antipattern: reporting RMSE without unit context.

### Sequence / Structured
- CTC loss: requires `blank` token; forward-backward algorithm.
- Triplet loss: margin > 0 required; hard negative mining.
- Contrastive: temperature τ critical; usually 0.07 (CLIP).

## 2. Numerical Stability Patterns

| Problem | Wrong | Right |
|---------|-------|-------|
| Log of softmax | `log(softmax(x))` | `log_softmax(x)` |
| Sigmoid + BCE | `BCELoss(sigmoid(x))` | `BCEWithLogitsLoss(x)` |
| Log-sum-exp | `log(sum(exp(x)))` | `torch.logsumexp(x)` |
| Division | `a / b` | `a / (b + eps)`, eps ≥ 1e-8 |
| Variance | `mean((x-mean)^2)` | `torch.var(x, unbiased=True)` |
| Softmax of logits | `exp(x)/sum(exp(x))` | `F.softmax(x, dim=-1)` — has implicit max-subtract |

## 3. Gradient and Backprop

### Mandatory training loop order
```python
optimizer.zero_grad()         # 1. clear stale grads
loss = criterion(model(x), y) # 2. forward
loss.backward()                # 3. backward
torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)  # 4. clip (RNN/Transformer)
optimizer.step()               # 5. update
```

### `detach()` placement
- Targets: always detach (`target.detach()`).
- Inputs: never detach (breaks gradient flow).
- Teacher model in distillation: detach outputs.

### Gradient accumulation
```python
loss = loss / accumulation_steps   # normalize
loss.backward()
if (step + 1) % accumulation_steps == 0:
    optimizer.step()
    optimizer.zero_grad()
```
Forgetting the division inflates effective LR by `accumulation_steps`×.

### Mixed precision (AMP)
```python
with torch.autocast(device_type='cuda', dtype=torch.bfloat16):  # BF16 preferred on your GPU architecture
    loss = criterion(model(x), y)
scaler.scale(loss).backward()
scaler.unscale_(optimizer)  # required before clipping under GradScaler
torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
scaler.step(optimizer)
scaler.update()
```

## 4. Optimizer and Scheduler Sanity

### AdamW parameter groups
Weight decay applies to weights, NOT to bias / LayerNorm / BatchNorm:
```python
decay, no_decay = [], []
for name, p in model.named_parameters():
    if 'bias' in name or 'norm' in name.lower():
        no_decay.append(p)
    else:
        decay.append(p)
optimizer = torch.optim.AdamW([
    {'params': decay, 'weight_decay': 0.01},
    {'params': no_decay, 'weight_decay': 0.0},
], lr=5e-5)
```

### LR defaults by architecture
| Architecture | Optimizer | LR | Warmup |
|--------------|-----------|----|--------|
| CNN / ResNet | SGD+momentum | 0.1 with cosine | 5 epochs |
| Transformer pretraining | AdamW | 1e-4 | 10k steps |
| LLM fine-tuning (full) | AdamW | 5e-5 | 3% of total |
| LoRA fine-tuning | AdamW | 1e-4 → 3e-4 | 3% of total |
| QLoRA (4-bit) | paged_adamw_32bit | 2e-4 | 3% of total |

### Scheduler step timing
- `CosineAnnealingLR`: `.step()` per epoch.
- `OneCycleLR`, `get_linear_schedule_with_warmup`: `.step()` per batch.
- Mismatching = catastrophic LR curve.

## 5. Initialization

| Activation | Initializer | Gain |
|------------|-------------|------|
| ReLU / LeakyReLU | Kaiming (He) normal | `sqrt(2)` |
| Tanh | Xavier (Glorot) normal | `1` |
| Sigmoid | Xavier normal | `1` |
| Embeddings (transformer) | N(0, 0.02) | — |
| Output layer (transformer) | N(0, 0.02 / sqrt(2*L)) | — |

Bias: initialize to zero. Weights never to zero (breaks symmetry).

## 6. Attention Mathematics

### Scaled dot-product attention
```
Attention(Q, K, V) = softmax(QK^T / sqrt(d_k)) V
```
`sqrt(d_k)` scale is NON-NEGOTIABLE — without it, gradients of softmax saturate at large `d_k`.

### Multi-head attention
Concat heads, project with `W_O`. Total params: `4 * d_model^2` (Q, K, V, O).

### Flash Attention 2
- Available on your GPU architecture.
- No math change — same output, O(N) memory instead of O(N^2).
- Check `flash_attn_func` signature matches your Q/K/V layout (batch × seqlen × heads × head_dim).

### Positional encoding
- Sinusoidal: deterministic, extrapolates poorly.
- Learned: parameterized, fixed max length.
- RoPE: relative, rotates Q/K by position angle. Modern default.
- ALiBi: attention bias, no explicit encoding, good extrapolation.

## 7. Sampling Strategies (LLMs)

### Temperature
```python
logits = logits / temperature
probs = F.softmax(logits, dim=-1)
```
- `T → 0`: greedy (argmax).
- `T = 1`: model's native distribution.
- `T > 1`: flatter, more random.
- Antipattern: applying temperature to probabilities instead of logits.

### Top-k / Top-p (nucleus)
Apply on LOGITS before softmax, not on probabilities:
```python
values, _ = torch.topk(logits, k)
logits[logits < values[..., -1:]] = -float('inf')
probs = F.softmax(logits, dim=-1)
```

### Repetition penalty
Divide logit of already-generated tokens by penalty > 1.0. Careful with prompt tokens.

## 8. Embeddings and Similarity

### Cosine similarity
Requires L2 normalization:
```python
a = F.normalize(a, dim=-1)
b = F.normalize(b, dim=-1)
cos_sim = (a * b).sum(-1)  # now in [-1, 1]
```
If not normalized, use dot product — don't call it cosine.

### Dot product vs cosine
- Dot product: magnitude matters (favors longer vectors).
- Cosine: magnitude-invariant, angle only.
- In RAG: cosine is standard. In dense retrieval trained with contrastive, often dot product.

## 9. RAG Scoring and Evaluation

### Retrieval metrics
- Recall@k: fraction of relevant docs in top-k.
- MRR: mean reciprocal rank of first relevant doc.
- NDCG: graded relevance, position-discounted.

### Generation metrics
- BLEU: n-gram precision. Use for translation.
- ROUGE: n-gram recall. Use for summarization.
- BERTScore: contextual embeddings. Correlates better with human judgment.
- RAGAS: faithfulness, answer relevance, context precision/recall. LLM-judge based.

### Perplexity
```
PPL = exp(loss)
```
Only valid if `loss` is MEAN cross-entropy in nats. Aggregating ppl over batches: `PPL = exp(mean(losses))`, NOT `mean(exp(losses))`.

## 10. Statistical Validity

### Hypothesis testing checklist
- Paired vs unpaired? (paired if same subjects measured twice)
- Parametric assumptions met? (normality via Shapiro-Wilk, equal variance via Levene)
- If violated → non-parametric (Mann-Whitney, Wilcoxon).
- Sample size sufficient? (n ≥ 30 rule of thumb for CLT).
- Multiple comparisons? → Bonferroni or FDR (Benjamini-Hochberg).

### Effect size (always report alongside p-value)
| Test | Effect size | Small / Med / Large |
|------|-------------|---------------------|
| t-test | Cohen's d | 0.2 / 0.5 / 0.8 |
| ANOVA | η² | 0.01 / 0.06 / 0.14 |
| Correlation | r | 0.1 / 0.3 / 0.5 |
| Chi-square | Cramér's V | 0.1 / 0.3 / 0.5 |

### Confidence intervals
Prefer bootstrap CIs for non-standard metrics (F1, AUC):
```python
from sklearn.utils import resample
scores = [metric(y_true_s, y_pred_s)
          for y_true_s, y_pred_s in (resample(y_true, y_pred) for _ in range(1000))]
ci_low, ci_high = np.percentile(scores, [2.5, 97.5])
```

## 11. Calibration

### Metrics
- Brier score: mean squared error between predicted prob and outcome. Target < 0.1.
- ECE (Expected Calibration Error): |confidence - accuracy| weighted by bin size.
- Reliability diagram: plot predicted confidence vs actual accuracy.

### Calibrators
- `CalibratedClassifierCV(method='isotonic')` — n > 1000.
- `CalibratedClassifierCV(method='sigmoid')` — n < 1000 (Platt scaling).
- Temperature scaling (DL): single scalar T applied to logits. Minimal, effective.

## 12. Reproducibility

```python
import random, numpy as np, torch
random.seed(42)
np.random.seed(42)
torch.manual_seed(42)
torch.cuda.manual_seed_all(42)
torch.backends.cudnn.deterministic = True
torch.backends.cudnn.benchmark = False
torch.use_deterministic_algorithms(True, warn_only=True)

def seed_worker(worker_id):
    w_seed = torch.initial_seed() % 2**32
    np.random.seed(w_seed)
    random.seed(w_seed)

g = torch.Generator(); g.manual_seed(42)
DataLoader(dataset, worker_init_fn=seed_worker, generator=g, num_workers=4)
```

Incomplete seeding → experiment does not exist.

## 13. Common Bugs — Detection Patterns

| Bug | grep/ripgrep pattern |
|-----|---------------------|
| log(softmax(...)) instead of log_softmax | `rg 'torch\.log\(.*softmax' src/` |
| Division without epsilon | `rg '/\s*\w+\.sum\(\)' src/` |
| Missing manual_seed | `rg 'manual_seed\|np\.random\.seed' src/` — expect ≥3 calls |
| Bare `.exp()` risking overflow | `rg 'torch\.exp\(' src/` — review each |
| Test set leak in preprocessing | `rg '\.fit\(.*test' src/` — should never match |
| SMOTE before split | `rg 'SMOTE.*fit_resample' -B 5 src/` — check fit is inside CV |
| `torch.no_grad()` wrapping training forward | `rg 'torch\.no_grad' src/` — review each |

## 14. Canonical References

| Topic | Source |
|-------|--------|
| Backpropagation | Goodfellow, Bengio, Courville — Deep Learning (Ch 6) |
| Optimization | Ruder (2016) — An overview of gradient descent optimization algorithms |
| Attention | Vaswani et al. (2017) — Attention Is All You Need |
| Flash Attention | Dao (2023) — FlashAttention-2 |
| RoPE | Su et al. (2021) — RoFormer |
| Calibration | Guo et al. (2017) — On Calibration of Modern Neural Networks |
| LoRA | Hu et al. (2021) — LoRA: Low-Rank Adaptation |
| QLoRA | Dettmers et al. (2023) — QLoRA: Efficient Finetuning |
| Bayesian stats | Gelman et al. — Bayesian Data Analysis (3rd ed) |
| Multiple testing | Benjamini & Hochberg (1995) |

<!-- ultrathink: extended thinking activo en esta skill/agent -->
