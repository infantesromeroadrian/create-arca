---
name: multimodal-ai
description: Complete guide for multimodal AI including vision-language models (CLIP, LLaVA, GPT-4V), audio-text (Whisper), document understanding, and multimodal embeddings. Use when building systems that combine images, text, audio, or video.
---

# Multimodal AI

> **ARCA preference:** dentro de proyectos ARCA, default a Claude Vision (`claude-sonnet-4-6` con bloque `image` nativo del SDK Anthropic). Los ejemplos OpenAI Vision (`gpt-4o` con `image_url` content-block) abajo se mantienen porque es la forma canónica del SDK de OpenAI; copiarlo a Anthropic SDK distorsiona el patrón upstream. La sección "Claude Vision" tras los OpenAI examples muestra la adaptación nativa.

## Stack 2025

| Component | Tools |
|-----------|-------|
| Vision-Language | CLIP, SigLIP, LLaVA, GPT-4V, Gemini |
| Audio-Text | Whisper, Seamless, MusicGen |
| Document AI | DocTR, LayoutLM, Donut |
| Video | VideoLLaMA, Twelve Labs |
| Embeddings | ImageBind, CLAP |
| Generation | Stable Diffusion, DALL-E, Midjourney |

---

## Vision-Language Models

### CLIP (Contrastive Language-Image Pre-training)

```python
from transformers import CLIPProcessor, CLIPModel
import torch
from PIL import Image

# Load model
model = CLIPModel.from_pretrained("openai/clip-vit-large-patch14")
processor = CLIPProcessor.from_pretrained("openai/clip-vit-large-patch14")

# Zero-shot classification
image = Image.open("cat.jpg")
labels = ["a photo of a cat", "a photo of a dog", "a photo of a car"]

inputs = processor(
    text=labels,
    images=image,
    return_tensors="pt",
    padding=True,
)

outputs = model(**inputs)
logits_per_image = outputs.logits_per_image
probs = logits_per_image.softmax(dim=1)

for label, prob in zip(labels, probs[0]):
    print(f"{label}: {prob:.2%}")

# Image-text similarity
def get_similarity(image, texts):
    inputs = processor(text=texts, images=image, return_tensors="pt", padding=True)
    outputs = model(**inputs)
    return outputs.logits_per_image.softmax(dim=1)

# Image embeddings
def get_image_embedding(image):
    inputs = processor(images=image, return_tensors="pt")
    return model.get_image_features(**inputs)

# Text embeddings
def get_text_embedding(text):
    inputs = processor(text=text, return_tensors="pt", padding=True)
    return model.get_text_features(**inputs)
```

### SigLIP (Better CLIP)

```python
from transformers import AutoProcessor, AutoModel
import torch

# SigLIP has better performance than CLIP
model = AutoModel.from_pretrained("google/siglip-so400m-patch14-384")
processor = AutoProcessor.from_pretrained("google/siglip-so400m-patch14-384")

# Same API as CLIP
inputs = processor(text=labels, images=image, return_tensors="pt", padding=True)
outputs = model(**inputs)

# SigLIP uses sigmoid instead of softmax
probs = torch.sigmoid(outputs.logits_per_image)
```

### Image Search with CLIP

```python
import faiss
import numpy as np
from PIL import Image
from pathlib import Path

class CLIPImageSearch:
    def __init__(self, model_name="openai/clip-vit-large-patch14"):
        self.model = CLIPModel.from_pretrained(model_name)
        self.processor = CLIPProcessor.from_pretrained(model_name)
        self.index = None
        self.image_paths = []
    
    def index_images(self, image_dir: str):
        """Index all images in directory."""
        image_paths = list(Path(image_dir).glob("*.jpg"))
        embeddings = []
        
        for path in image_paths:
            image = Image.open(path)
            inputs = self.processor(images=image, return_tensors="pt")
            
            with torch.no_grad():
                emb = self.model.get_image_features(**inputs)
                emb = emb / emb.norm(dim=-1, keepdim=True)
            
            embeddings.append(emb.numpy())
            self.image_paths.append(str(path))
        
        # Build FAISS index
        embeddings = np.vstack(embeddings).astype("float32")
        self.index = faiss.IndexFlatIP(embeddings.shape[1])
        self.index.add(embeddings)
    
    def search_by_text(self, query: str, k: int = 5):
        """Search images by text description."""
        inputs = self.processor(text=query, return_tensors="pt")
        
        with torch.no_grad():
            text_emb = self.model.get_text_features(**inputs)
            text_emb = text_emb / text_emb.norm(dim=-1, keepdim=True)
        
        scores, indices = self.index.search(text_emb.numpy().astype("float32"), k)
        
        return [(self.image_paths[i], scores[0][j]) for j, i in enumerate(indices[0])]
    
    def search_by_image(self, image_path: str, k: int = 5):
        """Search similar images."""
        image = Image.open(image_path)
        inputs = self.processor(images=image, return_tensors="pt")
        
        with torch.no_grad():
            img_emb = self.model.get_image_features(**inputs)
            img_emb = img_emb / img_emb.norm(dim=-1, keepdim=True)
        
        scores, indices = self.index.search(img_emb.numpy().astype("float32"), k)
        
        return [(self.image_paths[i], scores[0][j]) for j, i in enumerate(indices[0])]
```

---

## Vision-Language Models (VLMs)

### LLaVA (Local)

```python
from transformers import LlavaNextProcessor, LlavaNextForConditionalGeneration
import torch
from PIL import Image

# Load model
model = LlavaNextForConditionalGeneration.from_pretrained(
    "llava-hf/llava-v1.6-mistral-7b-hf",
    torch_dtype=torch.float16,
    device_map="auto",
)
processor = LlavaNextProcessor.from_pretrained("llava-hf/llava-v1.6-mistral-7b-hf")

# Image understanding
image = Image.open("chart.png")
prompt = "[INST] <image>\nDescribe this chart in detail. What trends do you see? [/INST]"

inputs = processor(prompt, image, return_tensors="pt").to(model.device)

output = model.generate(
    **inputs,
    max_new_tokens=500,
    do_sample=True,
    temperature=0.7,
)

response = processor.decode(output[0], skip_special_tokens=True)
print(response)
```

### GPT-4 Vision (API)

```python
from openai import OpenAI
import base64

client = OpenAI()

def encode_image(image_path):
    with open(image_path, "rb") as f:
        return base64.standard_b64encode(f.read()).decode("utf-8")

# Single image
response = client.chat.completions.create(
    model="gpt-4o",
    messages=[
        {
            "role": "user",
            "content": [
                {"type": "text", "text": "What's in this image?"},
                {
                    "type": "image_url",
                    "image_url": {
                        "url": f"data:image/jpeg;base64,{encode_image('photo.jpg')}",
                        "detail": "high",  # or "low", "auto"
                    },
                },
            ],
        }
    ],
    max_tokens=500,
)

print(response.choices[0].message.content)

# Multiple images
response = client.chat.completions.create(
    model="gpt-4o",
    messages=[
        {
            "role": "user",
            "content": [
                {"type": "text", "text": "Compare these two images:"},
                {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{encode_image('img1.jpg')}"}},
                {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{encode_image('img2.jpg')}"}},
            ],
        }
    ],
)
```

### Claude Vision (API)

```python
import anthropic
import base64

client = anthropic.Anthropic()

def encode_image(path):
    with open(path, "rb") as f:
        return base64.standard_b64encode(f.read()).decode("utf-8")

response = client.messages.create(
    model="claude-sonnet-4-20250514",
    max_tokens=1024,
    messages=[
        {
            "role": "user",
            "content": [
                {
                    "type": "image",
                    "source": {
                        "type": "base64",
                        "media_type": "image/jpeg",
                        "data": encode_image("image.jpg"),
                    },
                },
                {
                    "type": "text",
                    "text": "Analyze this image and extract any text you see.",
                },
            ],
        }
    ],
)

print(response.content[0].text)
```

---

## Audio-Text Models

### Whisper (Speech-to-Text)

```python
from transformers import WhisperProcessor, WhisperForConditionalGeneration
import torch
import librosa

# Load model
processor = WhisperProcessor.from_pretrained("openai/whisper-large-v3")
model = WhisperForConditionalGeneration.from_pretrained(
    "openai/whisper-large-v3",
    torch_dtype=torch.float16,
    device_map="auto",
)

# Transcribe audio
audio, sr = librosa.load("audio.mp3", sr=16000)

inputs = processor(audio, sampling_rate=16000, return_tensors="pt")
inputs = inputs.to(model.device, torch.float16)

# Generate with language detection
generated_ids = model.generate(
    inputs.input_features,
    max_new_tokens=448,
    language="en",  # or None for auto-detect
    task="transcribe",  # or "translate" for translation to English
)

transcription = processor.batch_decode(generated_ids, skip_special_tokens=True)[0]
print(transcription)

# With timestamps
generated_ids = model.generate(
    inputs.input_features,
    return_timestamps=True,
)
result = processor.batch_decode(generated_ids, skip_special_tokens=False, output_offsets=True)
```

### Whisper with faster-whisper

```python
from faster_whisper import WhisperModel

# Faster inference with CTranslate2
model = WhisperModel("large-v3", device="cuda", compute_type="float16")

segments, info = model.transcribe(
    "audio.mp3",
    beam_size=5,
    language="en",
    vad_filter=True,  # Filter silence
)

print(f"Detected language: {info.language} ({info.language_probability:.2%})")

for segment in segments:
    print(f"[{segment.start:.2f}s -> {segment.end:.2f}s] {segment.text}")
```

### Text-to-Speech

```python
from transformers import SpeechT5Processor, SpeechT5ForTextToSpeech, SpeechT5HifiGan
import torch
import soundfile as sf

processor = SpeechT5Processor.from_pretrained("microsoft/speecht5_tts")
model = SpeechT5ForTextToSpeech.from_pretrained("microsoft/speecht5_tts")
vocoder = SpeechT5HifiGan.from_pretrained("microsoft/speecht5_hifigan")

# Speaker embeddings
from datasets import load_dataset
embeddings_dataset = load_dataset("Matthijs/cmu-arctic-xvectors", split="validation")
speaker_embeddings = torch.tensor(embeddings_dataset[7306]["xvector"]).unsqueeze(0)

# Generate speech
inputs = processor(text="Hello, this is a test.", return_tensors="pt")
speech = model.generate_speech(inputs["input_ids"], speaker_embeddings, vocoder=vocoder)

sf.write("output.wav", speech.numpy(), samplerate=16000)
```

---

## Document Understanding

### Document OCR with DocTR

```python
from doctr.io import DocumentFile
from doctr.models import ocr_predictor

# Load model
model = ocr_predictor(det_arch="db_resnet50", reco_arch="crnn_vgg16_bn", pretrained=True)

# Process document
doc = DocumentFile.from_pdf("document.pdf")
# Or from images
doc = DocumentFile.from_images(["page1.jpg", "page2.jpg"])

# OCR
result = model(doc)

# Extract text
for page in result.pages:
    for block in page.blocks:
        for line in block.lines:
            text = " ".join([word.value for word in line.words])
            print(text)

# Export to JSON
result.export()
```

### LayoutLM for Document QA

```python
from transformers import LayoutLMv3Processor, LayoutLMv3ForQuestionAnswering
from PIL import Image
import torch

processor = LayoutLMv3Processor.from_pretrained("microsoft/layoutlmv3-base")
model = LayoutLMv3ForQuestionAnswering.from_pretrained("microsoft/layoutlmv3-base")

# Document QA
image = Image.open("invoice.png")
question = "What is the total amount?"

encoding = processor(
    image,
    question,
    return_tensors="pt",
    truncation=True,
    padding="max_length",
)

with torch.no_grad():
    outputs = model(**encoding)

# Get answer span
start_idx = outputs.start_logits.argmax()
end_idx = outputs.end_logits.argmax()

answer_tokens = encoding.input_ids[0][start_idx:end_idx+1]
answer = processor.tokenizer.decode(answer_tokens)
print(f"Answer: {answer}")
```

### Donut (Document Understanding Transformer)

```python
from transformers import DonutProcessor, VisionEncoderDecoderModel
from PIL import Image
import torch

processor = DonutProcessor.from_pretrained("naver-clova-ix/donut-base-finetuned-docvqa")
model = VisionEncoderDecoderModel.from_pretrained("naver-clova-ix/donut-base-finetuned-docvqa")

# Document QA (no OCR needed)
image = Image.open("document.png")
question = "What is the invoice number?"

# Prepare input
task_prompt = f"<s_docvqa><s_question>{question}</s_question><s_answer>"
decoder_input_ids = processor.tokenizer(task_prompt, add_special_tokens=False, return_tensors="pt").input_ids

pixel_values = processor(image, return_tensors="pt").pixel_values

# Generate
outputs = model.generate(
    pixel_values,
    decoder_input_ids=decoder_input_ids,
    max_length=model.config.decoder.max_position_embeddings,
    pad_token_id=processor.tokenizer.pad_token_id,
    eos_token_id=processor.tokenizer.eos_token_id,
)

# Decode
answer = processor.batch_decode(outputs, skip_special_tokens=True)[0]
print(answer)
```

---

## Unified Multimodal Embeddings

### ImageBind (Meta)

```python
import torch
from imagebind import data
from imagebind.models import imagebind_model
from imagebind.models.imagebind_model import ModalityType

# Load model
model = imagebind_model.imagebind_huge(pretrained=True)
model.eval()
model.to("cuda")

# Prepare inputs
text = data.load_and_transform_text(["a dog", "a cat"], "cuda")
image = data.load_and_transform_vision_data(["dog.jpg"], "cuda")
audio = data.load_and_transform_audio_data(["dog_bark.wav"], "cuda")

# Get embeddings
with torch.no_grad():
    embeddings = model({
        ModalityType.TEXT: text,
        ModalityType.VISION: image,
        ModalityType.AUDIO: audio,
    })

# Compare modalities
image_emb = embeddings[ModalityType.VISION]
text_emb = embeddings[ModalityType.TEXT]
audio_emb = embeddings[ModalityType.AUDIO]

# Cross-modal similarity
similarity = torch.softmax(image_emb @ text_emb.T, dim=-1)
print(f"Image-text similarity: {similarity}")
```

### CLAP (Audio-Text)

```python
from transformers import ClapProcessor, ClapModel
import librosa

model = ClapModel.from_pretrained("laion/clap-htsat-unfused")
processor = ClapProcessor.from_pretrained("laion/clap-htsat-unfused")

# Audio embedding
audio, sr = librosa.load("sound.wav", sr=48000)
inputs = processor(audios=audio, return_tensors="pt", sampling_rate=48000)
audio_embed = model.get_audio_features(**inputs)

# Text embedding
texts = ["dog barking", "cat meowing", "car horn"]
inputs = processor(text=texts, return_tensors="pt", padding=True)
text_embed = model.get_text_features(**inputs)

# Similarity
similarity = (audio_embed @ text_embed.T).softmax(dim=-1)
for text, score in zip(texts, similarity[0]):
    print(f"{text}: {score:.2%}")
```

---

## Video Understanding

### Video Captioning

```python
from transformers import AutoProcessor, AutoModelForVision2Seq
import torch
import av

def read_video_frames(video_path, num_frames=8):
    """Sample frames from video."""
    container = av.open(video_path)
    stream = container.streams.video[0]
    
    total_frames = stream.frames
    indices = np.linspace(0, total_frames - 1, num_frames).astype(int)
    
    frames = []
    for i, frame in enumerate(container.decode(video=0)):
        if i in indices:
            frames.append(frame.to_ndarray(format="rgb24"))
        if len(frames) == num_frames:
            break
    
    return np.stack(frames)

# Load model
processor = AutoProcessor.from_pretrained("llava-hf/LLaVA-NeXT-Video-7B-hf")
model = AutoModelForVision2Seq.from_pretrained(
    "llava-hf/LLaVA-NeXT-Video-7B-hf",
    torch_dtype=torch.float16,
    device_map="auto",
)

# Process video
frames = read_video_frames("video.mp4")
prompt = "Describe what happens in this video."

inputs = processor(text=prompt, images=frames, return_tensors="pt")
outputs = model.generate(**inputs, max_new_tokens=200)
caption = processor.decode(outputs[0], skip_special_tokens=True)
```

---

## Building Multimodal RAG

```python
from sentence_transformers import SentenceTransformer
from transformers import CLIPProcessor, CLIPModel
import faiss
import numpy as np

class MultimodalRAG:
    """RAG system supporting text and images."""
    
    def __init__(self):
        # Text encoder
        self.text_encoder = SentenceTransformer("all-MiniLM-L6-v2")
        
        # Image encoder (CLIP)
        self.clip_model = CLIPModel.from_pretrained("openai/clip-vit-base-patch32")
        self.clip_processor = CLIPProcessor.from_pretrained("openai/clip-vit-base-patch32")
        
        # Indices
        self.text_index = None
        self.image_index = None
        self.documents = []
        self.images = []
    
    def add_text(self, texts: list):
        """Index text documents."""
        embeddings = self.text_encoder.encode(texts, normalize_embeddings=True)
        
        if self.text_index is None:
            self.text_index = faiss.IndexFlatIP(embeddings.shape[1])
        
        self.text_index.add(embeddings.astype("float32"))
        self.documents.extend(texts)
    
    def add_images(self, image_paths: list, captions: list = None):
        """Index images with optional captions."""
        embeddings = []
        
        for path in image_paths:
            image = Image.open(path)
            inputs = self.clip_processor(images=image, return_tensors="pt")
            
            with torch.no_grad():
                emb = self.clip_model.get_image_features(**inputs)
                emb = emb / emb.norm(dim=-1, keepdim=True)
            
            embeddings.append(emb.numpy())
        
        embeddings = np.vstack(embeddings).astype("float32")
        
        if self.image_index is None:
            self.image_index = faiss.IndexFlatIP(embeddings.shape[1])
        
        self.image_index.add(embeddings)
        self.images.extend(list(zip(image_paths, captions or [None] * len(image_paths))))
    
    def search(self, query: str, k: int = 5, modalities: list = ["text", "image"]):
        """Search across modalities."""
        results = []
        
        if "text" in modalities and self.text_index:
            text_emb = self.text_encoder.encode([query], normalize_embeddings=True)
            scores, indices = self.text_index.search(text_emb.astype("float32"), k)
            
            for idx, score in zip(indices[0], scores[0]):
                results.append(("text", self.documents[idx], float(score)))
        
        if "image" in modalities and self.image_index:
            inputs = self.clip_processor(text=query, return_tensors="pt")
            
            with torch.no_grad():
                text_emb = self.clip_model.get_text_features(**inputs)
                text_emb = text_emb / text_emb.norm(dim=-1, keepdim=True)
            
            scores, indices = self.image_index.search(text_emb.numpy().astype("float32"), k)
            
            for idx, score in zip(indices[0], scores[0]):
                path, caption = self.images[idx]
                results.append(("image", {"path": path, "caption": caption}, float(score)))
        
        # Sort by score
        results.sort(key=lambda x: x[2], reverse=True)
        return results[:k]
```

---

## Anti-patterns

| [FAIL] Don't | [PASS] Do |
|----------|-------|
| Use CLIP for fine-grained recognition | Use specialized models or fine-tune |
| Ignore image resolution | Resize appropriately for model |
| Mix modality embeddings naively | Use aligned embedding spaces |
| Skip audio preprocessing | Normalize sample rate, length |
| Process long videos at once | Sample frames or chunk |
| Ignore OCR for documents | Combine VLM with OCR when needed |
