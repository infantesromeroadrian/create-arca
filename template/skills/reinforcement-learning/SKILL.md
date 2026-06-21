---
name: reinforcement-learning
description: Complete guide for reinforcement learning including DQN, PPO, SAC, multi-agent RL, RLHF for LLMs, and Gymnasium environments. Use when building game AI, robotics controllers, recommendation optimization, or fine-tuning LLMs with human feedback.
---

# Reinforcement Learning

## Stack 2025

| Component | Tools |
|-----------|-------|
| Environments | Gymnasium, PettingZoo, Unity ML-Agents |
| Algorithms | Stable-Baselines3, CleanRL, RLlib |
| RLHF | TRL, OpenRLHF, DeepSpeed-Chat |
| Distributed | Ray RLlib, Sample Factory |
| Visualization | Weights & Biases, TensorBoard |

---

## RL Fundamentals

### Algorithm Selection

| Algorithm | Type | Best For | Complexity |
|-----------|------|----------|------------|
| DQN | Value-based | Discrete actions | Medium |
| PPO | Policy gradient | General purpose | Medium |
| SAC | Actor-critic | Continuous control | High |
| A2C/A3C | Policy gradient | Parallel training | Medium |
| TD3 | Actor-critic | Continuous, stable | High |

### When to Use RL

| Use Case | Approach |
|----------|----------|
| Game AI | DQN, PPO |
| Robotics | SAC, TD3 |
| Recommendations | Contextual bandits, PPO |
| LLM Alignment | RLHF with PPO, DPO |
| Trading | PPO, SAC |

---

## Gymnasium Environments

### Basic Usage

```python
import gymnasium as gym

# Create environment
env = gym.make("CartPole-v1", render_mode="human")

# Environment info
print(f"Observation space: {env.observation_space}")
print(f"Action space: {env.action_space}")

# Basic loop
observation, info = env.reset()

for _ in range(1000):
    action = env.action_space.sample()  # Random action
    observation, reward, terminated, truncated, info = env.step(action)
    
    if terminated or truncated:
        observation, info = env.reset()

env.close()
```

### Custom Environment

```python
import gymnasium as gym
from gymnasium import spaces
import numpy as np

class TradingEnv(gym.Env):
    """Custom trading environment."""
    
    metadata = {"render_modes": ["human"]}
    
    def __init__(self, df, initial_balance=10000):
        super().__init__()
        
        self.df = df
        self.initial_balance = initial_balance
        
        # Actions: 0=hold, 1=buy, 2=sell
        self.action_space = spaces.Discrete(3)
        
        # Observation: price features + portfolio state
        self.observation_space = spaces.Box(
            low=-np.inf,
            high=np.inf,
            shape=(10,),  # Features
            dtype=np.float32,
        )
    
    def reset(self, seed=None):
        super().reset(seed=seed)
        
        self.current_step = 0
        self.balance = self.initial_balance
        self.shares = 0
        self.total_profit = 0
        
        return self._get_observation(), {}
    
    def step(self, action):
        current_price = self.df.iloc[self.current_step]["close"]
        
        # Execute action
        if action == 1:  # Buy
            shares_to_buy = self.balance // current_price
            self.shares += shares_to_buy
            self.balance -= shares_to_buy * current_price
        elif action == 2:  # Sell
            self.balance += self.shares * current_price
            self.shares = 0
        
        self.current_step += 1
        
        # Calculate reward (profit)
        portfolio_value = self.balance + self.shares * current_price
        reward = portfolio_value - self.initial_balance
        
        # Check if done
        terminated = self.current_step >= len(self.df) - 1
        truncated = False
        
        return self._get_observation(), reward, terminated, truncated, {}
    
    def _get_observation(self):
        row = self.df.iloc[self.current_step]
        return np.array([
            row["open"], row["high"], row["low"], row["close"],
            row["volume"], row["sma_20"], row["rsi"],
            self.balance, self.shares,
            self.balance + self.shares * row["close"],
        ], dtype=np.float32)

# Register environment
gym.register(
    id="Trading-v0",
    entry_point="__main__:TradingEnv",
    kwargs={"df": price_data},
)
```

---

## Stable-Baselines3

### DQN (Deep Q-Network)

```python
from stable_baselines3 import DQN
from stable_baselines3.common.env_util import make_vec_env
from stable_baselines3.common.callbacks import EvalCallback

# Vectorized environment
env = make_vec_env("CartPole-v1", n_envs=4)
eval_env = make_vec_env("CartPole-v1", n_envs=1)

# Create model
model = DQN(
    "MlpPolicy",
    env,
    learning_rate=1e-4,
    buffer_size=100000,
    learning_starts=1000,
    batch_size=64,
    tau=0.005,                    # Soft update coefficient
    gamma=0.99,                   # Discount factor
    train_freq=4,
    gradient_steps=1,
    target_update_interval=1000,
    exploration_fraction=0.1,
    exploration_final_eps=0.05,
    verbose=1,
    tensorboard_log="./logs/",
)

# Callbacks
eval_callback = EvalCallback(
    eval_env,
    best_model_save_path="./best_model/",
    log_path="./eval_logs/",
    eval_freq=10000,
    deterministic=True,
)

# Train
model.learn(
    total_timesteps=100000,
    callback=eval_callback,
    progress_bar=True,
)

# Save/Load
model.save("dqn_cartpole")
model = DQN.load("dqn_cartpole")

# Evaluate
from stable_baselines3.common.evaluation import evaluate_policy
mean_reward, std_reward = evaluate_policy(model, eval_env, n_eval_episodes=10)
print(f"Mean reward: {mean_reward:.2f} +/- {std_reward:.2f}")
```

### PPO (Proximal Policy Optimization)

```python
from stable_baselines3 import PPO

model = PPO(
    "MlpPolicy",
    env,
    learning_rate=3e-4,
    n_steps=2048,              # Steps per update
    batch_size=64,
    n_epochs=10,               # Epochs per update
    gamma=0.99,
    gae_lambda=0.95,           # GAE lambda
    clip_range=0.2,            # PPO clip range
    clip_range_vf=None,        # Value function clip
    ent_coef=0.01,             # Entropy coefficient
    vf_coef=0.5,               # Value function coefficient
    max_grad_norm=0.5,
    verbose=1,
    tensorboard_log="./logs/",
)

model.learn(total_timesteps=1000000)
```

### SAC (Soft Actor-Critic)

```python
from stable_baselines3 import SAC

# For continuous action spaces
env = gym.make("Pendulum-v1")

model = SAC(
    "MlpPolicy",
    env,
    learning_rate=3e-4,
    buffer_size=1000000,
    learning_starts=10000,
    batch_size=256,
    tau=0.005,
    gamma=0.99,
    train_freq=1,
    gradient_steps=1,
    ent_coef="auto",           # Auto-tune entropy
    target_entropy="auto",
    verbose=1,
)

model.learn(total_timesteps=500000)
```

### Custom Policy Networks

```python
from stable_baselines3 import PPO
from stable_baselines3.common.torch_layers import BaseFeaturesExtractor
import torch.nn as nn
import torch

class CustomCNN(BaseFeaturesExtractor):
    """Custom CNN for image observations."""
    
    def __init__(self, observation_space, features_dim=256):
        super().__init__(observation_space, features_dim)
        
        n_input_channels = observation_space.shape[0]
        
        self.cnn = nn.Sequential(
            nn.Conv2d(n_input_channels, 32, kernel_size=8, stride=4),
            nn.ReLU(),
            nn.Conv2d(32, 64, kernel_size=4, stride=2),
            nn.ReLU(),
            nn.Conv2d(64, 64, kernel_size=3, stride=1),
            nn.ReLU(),
            nn.Flatten(),
        )
        
        # Compute output size
        with torch.no_grad():
            n_flatten = self.cnn(
                torch.zeros(1, *observation_space.shape)
            ).shape[1]
        
        self.linear = nn.Linear(n_flatten, features_dim)
    
    def forward(self, observations):
        return self.linear(self.cnn(observations))

# Use custom extractor
policy_kwargs = {
    "features_extractor_class": CustomCNN,
    "features_extractor_kwargs": {"features_dim": 256},
    "net_arch": [256, 256],  # Policy/value network
}

model = PPO("CnnPolicy", env, policy_kwargs=policy_kwargs)
```

---

## CleanRL (Single-File Implementations)

### PPO Implementation

```python
import torch
import torch.nn as nn
import torch.optim as optim
from torch.distributions import Categorical
import numpy as np
import gymnasium as gym

class Agent(nn.Module):
    def __init__(self, env):
        super().__init__()
        obs_dim = np.prod(env.observation_space.shape)
        act_dim = env.action_space.n
        
        self.critic = nn.Sequential(
            nn.Linear(obs_dim, 64),
            nn.Tanh(),
            nn.Linear(64, 64),
            nn.Tanh(),
            nn.Linear(64, 1),
        )
        
        self.actor = nn.Sequential(
            nn.Linear(obs_dim, 64),
            nn.Tanh(),
            nn.Linear(64, 64),
            nn.Tanh(),
            nn.Linear(64, act_dim),
        )
    
    def get_value(self, x):
        return self.critic(x)
    
    def get_action_and_value(self, x, action=None):
        logits = self.actor(x)
        probs = Categorical(logits=logits)
        
        if action is None:
            action = probs.sample()
        
        return action, probs.log_prob(action), probs.entropy(), self.critic(x)

def train_ppo(env_id, total_timesteps=100000):
    env = gym.make(env_id)
    agent = Agent(env)
    optimizer = optim.Adam(agent.parameters(), lr=3e-4, eps=1e-5)
    
    # Hyperparameters
    num_steps = 128
    num_minibatches = 4
    update_epochs = 4
    clip_coef = 0.2
    gamma = 0.99
    gae_lambda = 0.95
    
    # Storage
    obs = torch.zeros((num_steps,) + env.observation_space.shape)
    actions = torch.zeros(num_steps)
    logprobs = torch.zeros(num_steps)
    rewards = torch.zeros(num_steps)
    dones = torch.zeros(num_steps)
    values = torch.zeros(num_steps)
    
    global_step = 0
    next_obs, _ = env.reset()
    next_obs = torch.tensor(next_obs)
    next_done = torch.zeros(1)
    
    while global_step < total_timesteps:
        # Rollout
        for step in range(num_steps):
            global_step += 1
            obs[step] = next_obs
            dones[step] = next_done
            
            with torch.no_grad():
                action, logprob, _, value = agent.get_action_and_value(next_obs)
            
            actions[step] = action
            logprobs[step] = logprob
            values[step] = value.flatten()
            
            next_obs, reward, terminated, truncated, _ = env.step(action.item())
            rewards[step] = reward
            next_obs = torch.tensor(next_obs)
            next_done = torch.tensor(float(terminated or truncated))
            
            if terminated or truncated:
                next_obs, _ = env.reset()
                next_obs = torch.tensor(next_obs)
        
        # GAE
        with torch.no_grad():
            next_value = agent.get_value(next_obs).flatten()
            advantages = torch.zeros_like(rewards)
            lastgaelam = 0
            
            for t in reversed(range(num_steps)):
                if t == num_steps - 1:
                    nextnonterminal = 1.0 - next_done
                    nextvalues = next_value
                else:
                    nextnonterminal = 1.0 - dones[t + 1]
                    nextvalues = values[t + 1]
                
                delta = rewards[t] + gamma * nextvalues * nextnonterminal - values[t]
                advantages[t] = lastgaelam = delta + gamma * gae_lambda * nextnonterminal * lastgaelam
            
            returns = advantages + values
        
        # Update
        batch_size = num_steps
        minibatch_size = batch_size // num_minibatches
        
        b_obs = obs.reshape((-1,) + env.observation_space.shape)
        b_actions = actions.reshape(-1)
        b_logprobs = logprobs.reshape(-1)
        b_advantages = advantages.reshape(-1)
        b_returns = returns.reshape(-1)
        
        for _ in range(update_epochs):
            indices = torch.randperm(batch_size)
            
            for start in range(0, batch_size, minibatch_size):
                end = start + minibatch_size
                mb_indices = indices[start:end]
                
                _, newlogprob, entropy, newvalue = agent.get_action_and_value(
                    b_obs[mb_indices], b_actions[mb_indices].long()
                )
                
                logratio = newlogprob - b_logprobs[mb_indices]
                ratio = logratio.exp()
                
                mb_advantages = b_advantages[mb_indices]
                mb_advantages = (mb_advantages - mb_advantages.mean()) / (mb_advantages.std() + 1e-8)
                
                # Policy loss
                pg_loss1 = -mb_advantages * ratio
                pg_loss2 = -mb_advantages * torch.clamp(ratio, 1 - clip_coef, 1 + clip_coef)
                pg_loss = torch.max(pg_loss1, pg_loss2).mean()
                
                # Value loss
                v_loss = 0.5 * ((newvalue.flatten() - b_returns[mb_indices]) ** 2).mean()
                
                # Entropy loss
                entropy_loss = entropy.mean()
                
                loss = pg_loss - 0.01 * entropy_loss + 0.5 * v_loss
                
                optimizer.zero_grad()
                loss.backward()
                nn.utils.clip_grad_norm_(agent.parameters(), 0.5)
                optimizer.step()
    
    return agent
```

---

## RLHF (Reinforcement Learning from Human Feedback)

### With TRL Library

```python
from trl import PPOTrainer, PPOConfig, AutoModelForCausalLMWithValueHead
from transformers import AutoTokenizer
import torch

# Load model with value head
model = AutoModelForCausalLMWithValueHead.from_pretrained("gpt2")
tokenizer = AutoTokenizer.from_pretrained("gpt2")
tokenizer.pad_token = tokenizer.eos_token

# Reference model (frozen)
ref_model = AutoModelForCausalLMWithValueHead.from_pretrained("gpt2")

# PPO config
config = PPOConfig(
    model_name="gpt2",
    learning_rate=1e-5,
    batch_size=16,
    mini_batch_size=4,
    gradient_accumulation_steps=1,
    ppo_epochs=4,
    init_kl_coef=0.2,
    target_kl=6.0,
    cliprange=0.2,
    cliprange_value=0.2,
)

# Reward model (pretrained)
reward_model = load_reward_model()

# PPO Trainer
ppo_trainer = PPOTrainer(
    config=config,
    model=model,
    ref_model=ref_model,
    tokenizer=tokenizer,
)

# Training loop
for batch in dataloader:
    query_tensors = tokenizer(batch["query"], return_tensors="pt", padding=True)["input_ids"]
    
    # Generate responses
    response_tensors = ppo_trainer.generate(
        query_tensors,
        max_new_tokens=50,
        do_sample=True,
        top_k=50,
    )
    
    # Compute rewards
    texts = [tokenizer.decode(r) for r in response_tensors]
    rewards = [reward_model(text) for text in texts]
    rewards = [torch.tensor(r) for r in rewards]
    
    # PPO step
    stats = ppo_trainer.step(query_tensors.tolist(), response_tensors.tolist(), rewards)
    
    print(f"Mean reward: {stats['ppo/mean_scores']:.4f}")
```

### Reward Model Training

```python
from transformers import AutoModelForSequenceClassification, Trainer, TrainingArguments
import torch.nn as nn

class RewardModel(nn.Module):
    def __init__(self, model_name):
        super().__init__()
        self.model = AutoModelForSequenceClassification.from_pretrained(
            model_name,
            num_labels=1,
        )
    
    def forward(self, input_ids, attention_mask):
        outputs = self.model(input_ids=input_ids, attention_mask=attention_mask)
        return outputs.logits.squeeze(-1)

# Preference dataset: (prompt, chosen, rejected)
class PreferenceDataset(torch.utils.data.Dataset):
    def __init__(self, data, tokenizer, max_length=512):
        self.data = data
        self.tokenizer = tokenizer
        self.max_length = max_length
    
    def __len__(self):
        return len(self.data)
    
    def __getitem__(self, idx):
        item = self.data[idx]
        
        chosen = self.tokenizer(
            item["prompt"] + item["chosen"],
            max_length=self.max_length,
            truncation=True,
            padding="max_length",
            return_tensors="pt",
        )
        
        rejected = self.tokenizer(
            item["prompt"] + item["rejected"],
            max_length=self.max_length,
            truncation=True,
            padding="max_length",
            return_tensors="pt",
        )
        
        return {
            "chosen_input_ids": chosen["input_ids"].squeeze(),
            "chosen_attention_mask": chosen["attention_mask"].squeeze(),
            "rejected_input_ids": rejected["input_ids"].squeeze(),
            "rejected_attention_mask": rejected["attention_mask"].squeeze(),
        }

# Pairwise ranking loss
def compute_loss(model, batch):
    chosen_rewards = model(
        batch["chosen_input_ids"],
        batch["chosen_attention_mask"],
    )
    rejected_rewards = model(
        batch["rejected_input_ids"],
        batch["rejected_attention_mask"],
    )
    
    # Bradley-Terry model
    loss = -torch.log(torch.sigmoid(chosen_rewards - rejected_rewards)).mean()
    return loss
```

---

## Multi-Agent RL

### PettingZoo

```python
from pettingzoo.mpe import simple_spread_v3
from stable_baselines3 import PPO
from supersuit import pettingzoo_env_to_vec_env_v1, concat_vec_envs_v1

# Create multi-agent environment
env = simple_spread_v3.parallel_env()

# Convert to vectorized environment
env = pettingzoo_env_to_vec_env_v1(env)
env = concat_vec_envs_v1(env, num_vec_envs=8, num_cpus=4)

# Train with parameter sharing
model = PPO("MlpPolicy", env, verbose=1)
model.learn(total_timesteps=1000000)
```

### Independent Learners

```python
from pettingzoo.classic import chess_v5

env = chess_v5.env()

# Separate model per agent
agents = {}
for agent in env.possible_agents:
    agents[agent] = PPO("MlpPolicy", env, verbose=0)

# Training loop
for episode in range(1000):
    env.reset()
    
    for agent in env.agent_iter():
        observation, reward, termination, truncation, info = env.last()
        
        if termination or truncation:
            action = None
        else:
            action, _ = agents[agent].predict(observation)
        
        env.step(action)
```

---

## Distributed Training

### Ray RLlib

```python
from ray import tune
from ray.rllib.algorithms.ppo import PPOConfig

config = (
    PPOConfig()
    .environment("CartPole-v1")
    .framework("torch")
    .rollouts(num_rollout_workers=4)
    .training(
        lr=3e-4,
        train_batch_size=4000,
        sgd_minibatch_size=128,
        num_sgd_iter=10,
    )
    .resources(num_gpus=1)
)

# Train
tune.run(
    "PPO",
    config=config.to_dict(),
    stop={"episode_reward_mean": 200},
    checkpoint_freq=10,
)

# Or direct training
algo = config.build()
for i in range(100):
    result = algo.train()
    print(f"Episode {i}: reward={result['episode_reward_mean']:.2f}")
```

---

## Evaluation & Debugging

```python
from stable_baselines3.common.evaluation import evaluate_policy
from stable_baselines3.common.monitor import Monitor
import numpy as np

# Evaluate policy
mean_reward, std_reward = evaluate_policy(
    model,
    env,
    n_eval_episodes=100,
    deterministic=True,
)

# Record videos
from stable_baselines3.common.vec_env import VecVideoRecorder

env = VecVideoRecorder(
    env,
    video_folder="./videos/",
    record_video_trigger=lambda x: x % 1000 == 0,
    video_length=200,
)

# Debug: Check value estimates
obs, _ = env.reset()
for _ in range(100):
    action, _ = model.predict(obs)
    value = model.policy.predict_values(torch.tensor(obs).unsqueeze(0))
    print(f"Value estimate: {value.item():.2f}")
    obs, reward, done, _, _ = env.step(action)
```

---

## Anti-patterns

| [FAIL] Don't | [PASS] Do |
|----------|-------|
| Skip reward shaping | Design informative rewards |
| Use sparse rewards only | Add intermediate rewards |
| Train without normalization | Normalize observations/rewards |
| Ignore exploration | Tune entropy/exploration params |
| Skip hyperparameter tuning | Use grid search or Optuna |
| Train on single seed | Average over multiple seeds |
