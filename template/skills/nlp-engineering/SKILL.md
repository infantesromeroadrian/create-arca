---
name: nlp-engineering
description: Complete guide for NLP engineering including text preprocessing, tokenization, transformers (BERT, RoBERTa), NER, classification, embeddings, and modern NLP pipelines. Use when building text classification, entity extraction, sentiment analysis, or text processing systems.
paths:
  - "**/nlp/**"
  - "**/text*.py"
---

# NLP Engineering

> **NOTE sobre tokenización:** `tiktoken.encoding_for_model("gpt-4o")` selecciona el vocabulario BPE de OpenAI para token counting — NO es invocación de modelo. Para contar tokens contra Claude usar `anthropic.Anthropic().messages.count_tokens(...)` (ver skill `anthropic-sdk`). Los ejemplos de tiktoken se mantienen para casos donde se cuenta contra OpenAI explícitamente.

## Stack 2025

| Component | Tools |
|-----------|-------|
| Framework | HuggingFace Transformers, spaCy |
| Embeddings | sentence-transformers, OpenAI, Cohere |
| Tokenization | tiktoken, tokenizers, sentencepiece |
| NER | spaCy, GLiNER, transformers |
| Classification | SetFit, transformers, sklearn |
| Processing | NLTK, textacy, ftfy |

---

## Text Preprocessing

### Cleaning Pipeline

```python
import re
import ftfy
from unidecode import unidecode

def clean_text(text: str) -> str:
    # Fix encoding issues
    text = ftfy.fix_text(text)
    
    # Normalize unicode
    text = unidecode(text)
    
    # Remove URLs
    text = re.sub(r'https?://\S+|www\.\S+', '', text)
    
    # Remove HTML tags
    text = re.sub(r'<[^>]+>', '', text)
    
    # Remove extra whitespace
    text = re.sub(r'\s+', ' ', text).strip()
    
    return text

# For specific domains
def clean_social_media(text: str) -> str:
    text = clean_text(text)
    # Remove mentions
    text = re.sub(r'@\w+', '', text)
    # Remove hashtags (keep text)
    text = re.sub(r'#(\w+)', r'\1', text)
    # Remove emojis (optional)
    text = re.sub(r'[\U00010000-\U0010ffff]', '', text)
    return text
```

### Language Detection

```python
from langdetect import detect, detect_langs
from lingua import Language, LanguageDetectorBuilder

# Simple detection
lang = detect("Bonjour le monde")  # 'fr'

# With confidence
langs = detect_langs("Hello world")  # [en:0.99]

# More accurate (lingua)
detector = LanguageDetectorBuilder.from_all_languages().build()
lang = detector.detect_language_of("Hola mundo")  # Language.SPANISH
confidence = detector.compute_language_confidence_values("Hello")
```

---

## Tokenization

### HuggingFace Tokenizers

```python
from transformers import AutoTokenizer

tokenizer = AutoTokenizer.from_pretrained("bert-base-uncased")

# Basic tokenization
tokens = tokenizer.tokenize("Hello, how are you?")
# ['hello', ',', 'how', 'are', 'you', '?']

# Full encoding
encoded = tokenizer(
    "Hello, how are you?",
    padding="max_length",
    truncation=True,
    max_length=512,
    return_tensors="pt",
)
# {'input_ids': tensor(...), 'attention_mask': tensor(...)}

# Batch encoding
texts = ["First text", "Second text"]
batch = tokenizer(texts, padding=True, truncation=True, return_tensors="pt")

# Decode back
text = tokenizer.decode(encoded["input_ids"][0], skip_special_tokens=True)
```

### tiktoken (OpenAI)

```python
import tiktoken

# Get encoding for model
enc = tiktoken.encoding_for_model("gpt-4o")
# Or by name
enc = tiktoken.get_encoding("cl100k_base")

# Encode/decode
tokens = enc.encode("Hello world")  # [9906, 1917]
text = enc.decode(tokens)  # "Hello world"

# Count tokens
def count_tokens(text: str, model: str = "gpt-4o") -> int:
    enc = tiktoken.encoding_for_model(model)
    return len(enc.encode(text))
```

### Tokenizer Comparison

| Tokenizer | Vocab Size | Use Case |
|-----------|------------|----------|
| BPE (GPT) | 50k-100k | General text |
| WordPiece (BERT) | 30k | Bidirectional models |
| SentencePiece | Configurable | Multilingual |
| Unigram | Variable | Subword regularization |

---

## Text Embeddings

### sentence-transformers

```python
from sentence_transformers import SentenceTransformer

# Load model
model = SentenceTransformer("all-MiniLM-L6-v2")
# Or newer models
model = SentenceTransformer("BAAI/bge-large-en-v1.5")
model = SentenceTransformer("nomic-ai/nomic-embed-text-v1.5")

# Single text
embedding = model.encode("Hello world")  # np.array (384,)

# Batch encoding
texts = ["First sentence", "Second sentence"]
embeddings = model.encode(texts, show_progress_bar=True)

# With normalization
embeddings = model.encode(texts, normalize_embeddings=True)

# Similarity
from sentence_transformers.util import cos_sim
similarity = cos_sim(embeddings[0], embeddings[1])
```

### Embedding Selection Guide

| Model | Dimensions | Speed | Quality |
|-------|------------|-------|---------|
| all-MiniLM-L6-v2 | 384 | Very Fast | Good |
| bge-large-en-v1.5 | 1024 | Medium | Excellent |
| nomic-embed-text-v1.5 | 768 | Fast | Excellent |
| text-embedding-3-large | 3072 | API | Best |
| voyage-3 | 1024 | API | Best |

### Custom Fine-tuning

```python
from sentence_transformers import SentenceTransformer, InputExample, losses
from torch.utils.data import DataLoader

model = SentenceTransformer("all-MiniLM-L6-v2")

# Prepare training data
train_examples = [
    InputExample(texts=["query", "positive doc"], label=1.0),
    InputExample(texts=["query", "negative doc"], label=0.0),
]

train_dataloader = DataLoader(train_examples, shuffle=True, batch_size=16)

# Contrastive loss
train_loss = losses.CosineSimilarityLoss(model)

# Train
model.fit(
    train_objectives=[(train_dataloader, train_loss)],
    epochs=1,
    warmup_steps=100,
)

model.save("./fine-tuned-embeddings")
```

---

## Text Classification

### Transformers Pipeline

```python
from transformers import pipeline

# Sentiment analysis
classifier = pipeline("sentiment-analysis")
result = classifier("I love this product!")
# [{'label': 'POSITIVE', 'score': 0.9998}]

# Zero-shot classification
classifier = pipeline("zero-shot-classification")
result = classifier(
    "This is about cooking recipes",
    candidate_labels=["food", "sports", "technology"],
)
# {'labels': ['food', 'sports', 'technology'], 'scores': [0.95, 0.03, 0.02]}

# Multi-label
result = classifier(
    "Apple released a new iPhone",
    candidate_labels=["technology", "business", "food"],
    multi_label=True,
)
```

### Fine-tuning for Classification

```python
from transformers import (
    AutoModelForSequenceClassification,
    AutoTokenizer,
    TrainingArguments,
    Trainer,
)
from datasets import load_dataset
import numpy as np
from sklearn.metrics import accuracy_score, f1_score

# Load data
dataset = load_dataset("imdb")
tokenizer = AutoTokenizer.from_pretrained("distilbert-base-uncased")

def tokenize(examples):
    return tokenizer(examples["text"], truncation=True, padding="max_length")

tokenized = dataset.map(tokenize, batched=True)

# Load model
model = AutoModelForSequenceClassification.from_pretrained(
    "distilbert-base-uncased",
    num_labels=2,
)

# Metrics
def compute_metrics(eval_pred):
    preds, labels = eval_pred
    preds = np.argmax(preds, axis=1)
    return {
        "accuracy": accuracy_score(labels, preds),
        "f1": f1_score(labels, preds, average="weighted"),
    }

# Training
training_args = TrainingArguments(
    output_dir="./results",
    num_train_epochs=3,
    per_device_train_batch_size=16,
    per_device_eval_batch_size=64,
    eval_strategy="epoch",
    save_strategy="epoch",
    learning_rate=2e-5,
    weight_decay=0.01,
    load_best_model_at_end=True,
)

trainer = Trainer(
    model=model,
    args=training_args,
    train_dataset=tokenized["train"],
    eval_dataset=tokenized["test"],
    compute_metrics=compute_metrics,
)

trainer.train()
```

### SetFit (Few-Shot)

```python
from setfit import SetFitModel, Trainer, sample_dataset
from datasets import load_dataset

# Load and sample few examples
dataset = load_dataset("emotion")
train_dataset = sample_dataset(dataset["train"], label_column="label", num_samples=8)

# Train
model = SetFitModel.from_pretrained("sentence-transformers/all-MiniLM-L6-v2")

trainer = Trainer(
    model=model,
    train_dataset=train_dataset,
    eval_dataset=dataset["test"],
)

trainer.train()

# Inference
preds = model.predict(["I'm so happy!", "This is terrible"])
```

---

## Named Entity Recognition

### spaCy NER

```python
import spacy

nlp = spacy.load("en_core_web_trf")  # Transformer-based

doc = nlp("Apple Inc. was founded by Steve Jobs in Cupertino, California.")

for ent in doc.ents:
    print(f"{ent.text}: {ent.label_}")
# Apple Inc.: ORG
# Steve Jobs: PERSON
# Cupertino: GPE
# California: GPE

# Entity types: PERSON, ORG, GPE, DATE, MONEY, PRODUCT, EVENT, etc.
```

### GLiNER (Zero-Shot NER)

```python
from gliner import GLiNER

model = GLiNER.from_pretrained("urchade/gliner_large-v2.1")

text = "The iPhone 15 Pro was released by Apple in September 2023."

# Custom entity types
labels = ["product", "company", "date", "technology"]

entities = model.predict_entities(text, labels, threshold=0.5)
for entity in entities:
    print(f"{entity['text']}: {entity['label']} ({entity['score']:.2f})")
# iPhone 15 Pro: product (0.92)
# Apple: company (0.95)
# September 2023: date (0.88)
```

### Transformers NER

```python
from transformers import pipeline

ner = pipeline("ner", model="dslim/bert-base-NER", aggregation_strategy="simple")

text = "Hugging Face is based in New York City."
entities = ner(text)
# [{'entity_group': 'ORG', 'word': 'Hugging Face', 'score': 0.99},
#  {'entity_group': 'LOC', 'word': 'New York City', 'score': 0.99}]
```

### Custom NER Training

```python
from transformers import (
    AutoModelForTokenClassification,
    AutoTokenizer,
    TrainingArguments,
    Trainer,
    DataCollatorForTokenClassification,
)
from datasets import load_dataset
import evaluate

# Load CoNLL format dataset
dataset = load_dataset("conll2003")

label_list = dataset["train"].features["ner_tags"].feature.names
# ['O', 'B-PER', 'I-PER', 'B-ORG', 'I-ORG', ...]

tokenizer = AutoTokenizer.from_pretrained("bert-base-cased")
model = AutoModelForTokenClassification.from_pretrained(
    "bert-base-cased",
    num_labels=len(label_list),
)

def tokenize_and_align_labels(examples):
    tokenized = tokenizer(examples["tokens"], truncation=True, is_split_into_words=True)
    labels = []
    for i, label in enumerate(examples["ner_tags"]):
        word_ids = tokenized.word_ids(batch_index=i)
        label_ids = []
        for word_idx in word_ids:
            if word_idx is None:
                label_ids.append(-100)
            else:
                label_ids.append(label[word_idx])
        labels.append(label_ids)
    tokenized["labels"] = labels
    return tokenized

tokenized = dataset.map(tokenize_and_align_labels, batched=True)

# Train
trainer = Trainer(
    model=model,
    args=TrainingArguments(output_dir="./ner", num_train_epochs=3),
    train_dataset=tokenized["train"],
    eval_dataset=tokenized["validation"],
    data_collator=DataCollatorForTokenClassification(tokenizer),
)

trainer.train()
```

---

## Semantic Search

### Basic Pipeline

```python
from sentence_transformers import SentenceTransformer
import numpy as np

model = SentenceTransformer("BAAI/bge-large-en-v1.5")

# Index documents
documents = ["Document 1...", "Document 2...", "Document 3..."]
doc_embeddings = model.encode(documents, normalize_embeddings=True)

# Query
query = "What is machine learning?"
query_embedding = model.encode(query, normalize_embeddings=True)

# Cosine similarity (dot product for normalized vectors)
scores = np.dot(doc_embeddings, query_embedding)
top_indices = np.argsort(scores)[::-1][:5]

for idx in top_indices:
    print(f"{scores[idx]:.3f}: {documents[idx][:100]}...")
```

### With FAISS

```python
import faiss
import numpy as np

# Create index
dimension = 1024
index = faiss.IndexFlatIP(dimension)  # Inner product for cosine sim

# Add normalized vectors
doc_embeddings = model.encode(documents, normalize_embeddings=True)
index.add(doc_embeddings.astype("float32"))

# Search
query_embedding = model.encode([query], normalize_embeddings=True)
scores, indices = index.search(query_embedding.astype("float32"), k=5)

# With IVF for large datasets
nlist = 100  # Number of clusters
quantizer = faiss.IndexFlatIP(dimension)
index = faiss.IndexIVFFlat(quantizer, dimension, nlist, faiss.METRIC_INNER_PRODUCT)
index.train(doc_embeddings)
index.add(doc_embeddings)
index.nprobe = 10  # Search 10 clusters
```

---

## Text Generation Utilities

### Prompt Templates

```python
from jinja2 import Template

template = Template("""
You are a helpful assistant.

Context:
{% for doc in documents %}
- {{ doc }}
{% endfor %}

Question: {{ question }}

Answer based only on the context above.
""")

prompt = template.render(
    documents=["Doc 1", "Doc 2"],
    question="What is AI?"
)
```

### Output Parsing

```python
import re
import json

def extract_json(text: str) -> dict:
    """Extract JSON from LLM response."""
    # Try direct parse
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    
    # Find JSON in markdown blocks
    match = re.search(r'```(?:json)?\s*([\s\S]*?)\s*```', text)
    if match:
        return json.loads(match.group(1))
    
    # Find JSON objects
    match = re.search(r'\{[\s\S]*\}', text)
    if match:
        return json.loads(match.group())
    
    raise ValueError("No valid JSON found")

def extract_list(text: str) -> list:
    """Extract bullet points or numbered list."""
    patterns = [
        r'^\s*[-*•]\s*(.+)$',  # Bullet points
        r'^\s*\d+[.)]\s*(.+)$',  # Numbered
    ]
    items = []
    for line in text.split('\n'):
        for pattern in patterns:
            match = re.match(pattern, line)
            if match:
                items.append(match.group(1).strip())
                break
    return items
```

---

## Evaluation Metrics

```python
from sklearn.metrics import classification_report, confusion_matrix
import evaluate

# Classification
print(classification_report(y_true, y_pred, target_names=class_names))

# NER (seqeval)
seqeval = evaluate.load("seqeval")
results = seqeval.compute(predictions=pred_labels, references=true_labels)
# {'precision': 0.92, 'recall': 0.91, 'f1': 0.91}

# Text similarity
from sentence_transformers import util
cos_sim = util.cos_sim(emb1, emb2)

# BLEU for generation
bleu = evaluate.load("bleu")
results = bleu.compute(predictions=preds, references=refs)

# BERTScore
bertscore = evaluate.load("bertscore")
results = bertscore.compute(predictions=preds, references=refs, lang="en")
```

---

## Anti-patterns

| [FAIL] Don't | [PASS] Do |
|----------|-------|
| Skip text cleaning | Clean and normalize before processing |
| Use wrong tokenizer | Match tokenizer to model |
| Ignore max length | Truncate/chunk long texts properly |
| Fine-tune with little data | Use few-shot methods (SetFit, zero-shot) |
| Hardcode entity types | Use zero-shot NER (GLiNER) for flexibility |
| Ignore multilingual needs | Use multilingual models when needed |
