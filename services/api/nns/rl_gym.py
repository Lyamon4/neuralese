# rl_gym.py
import gymnasium as gym
import torch
import numpy as np


class GymIterable:
	"""
	Adapter that makes a Gymnasium environment behave like a dataset iterator.
	Designed to integrate with model_core's Context, using ctx.extra["rl"] hooks:
	- policy(obs) -> action
	- action_fn(obs) -> action (fallback)
	- reward_fn(reward, obs, action, next_obs) -> shaped reward
	- preprocess_fn(obs) -> transformed observation
	"""

	def __init__(
		self,
		env_name: str,
		max_steps: int = 10000,
		device: torch.device | None = None,
		policy_fn=None,
		action_fn=None,
		reward_fn=None,
		preprocess_fn=None,
	):
		self.env = gym.make(env_name)
		self.device = device or torch.device("cpu")
		self.max_steps = max_steps

		# optional behavior hooks (can be overridden via ctx.extra["rl"])
		self.policy_fn = policy_fn
		self.action_fn = action_fn
		self.reward_fn = reward_fn
		self.preprocess_fn = preprocess_fn

		# environment spaces info (so other code can inspect shape/action dims)
		self.obs_space = self.env.observation_space
		self.act_space = self.env.action_space
		self.obs_shape = getattr(self.obs_space, "shape", None)
		self.act_shape = getattr(self.act_space, "shape", None)

	def _choose_action(self, obs):
		"""Determine the next action from provided hooks or random fallback."""
		# policy_fn (usually model-based)
		if callable(self.policy_fn):
			try:
				return self.policy_fn(obs)
			except Exception as e:
				print(f"[GymIterable] policy_fn error: {e}")
				pass

		# fallback action_fn
		if callable(self.action_fn):
			try:
				a = self.action_fn(obs)
				if a is not None:
					return a
			except Exception as e:
				print(f"[GymIterable] action_fn error: {e}")
				pass

		# default random sample
		return self.env.action_space.sample()

	def _shape_reward(self, reward, obs, action, next_obs):
		"""Apply optional reward shaping."""
		if callable(self.reward_fn):
			try:
				return self.reward_fn(reward, obs, action, next_obs)
			except Exception as e:
				print(f"[GymIterable] reward_fn error: {e}")
		return reward

	def _preprocess_obs(self, obs):
		"""Preprocess observation if hook provided."""
		if callable(self.preprocess_fn):
			try:
				return self.preprocess_fn(obs)
			except Exception as e:
				print(f"[GymIterable] preprocess_fn error: {e}")
		return obs

	def __iter__(self):
		obs, _ = self.env.reset()

		for step in range(self.max_steps):
			obs = self._preprocess_obs(obs)
			action = self._choose_action(obs)
			next_obs, reward, done, truncated, _ = self.env.step(action)
			reward = self._shape_reward(reward, obs, action, next_obs)

			# Convert everything to tensors for downstream training
			x = torch.as_tensor(obs, dtype=torch.float32, device=self.device)
			y = torch.as_tensor(action, dtype=torch.float32, device=self.device)
			r = torch.as_tensor(reward, dtype=torch.float32, device=self.device)

			yield x, y, r

			obs = next_obs
			if done or truncated:
				obs, _ = self.env.reset()
#
#
# env_name = "CartPole-v1"  # or any simple 1D-control env
# it = GymIterable(env_name, max_steps=10)
#
# print("=== Random policy ===")
# for i, (x, y, r) in enumerate(it):
# 	print(f"Step {i:02d} | obs={x.shape} | action={y} | reward={r}")
# 	if i >= 4:  # just first 5 steps
# 		break
#
#
# # --- 2. Custom model-like policy ---
# def fake_policy(obs):
# 	# Example: deterministic based on first feature
# 	if isinstance(obs, np.ndarray):
# 		return 0 if obs[2] < 0 else 1
# 	return 0
#
# print("\n=== Custom policy (fake_policy) ===")
# it2 = GymIterable(env_name, max_steps=10, policy_fn=fake_policy)
# for i, (x, y, r) in enumerate(it2):
# 	print(f"Step {i:02d} | obs[2]={x[2].item():+.3f} | policy_action={int(y.item())} | reward={r:.2f}")
# 	if i >= 4:
# 		break
#
#
# # --- 3. Torch-based example policy ---
# def torch_policy(obs):
# 	obs_t = torch.tensor(obs, dtype=torch.float32).unsqueeze(0)
# 	with torch.no_grad():
# 		# dummy linear weights, replace with real model later
# 		return int((obs_t[0, 2] > 0).item())
#
# print("\n=== Torch policy ===")
# it3 = GymIterable(env_name, max_steps=10, policy_fn=torch_policy)
# for i, (x, y, r) in enumerate(it3):
# 	print(f"Step {i:02d} | torch_action={int(y.item())} | reward={r:.2f}")
# 	if i >= 4:
# 		break