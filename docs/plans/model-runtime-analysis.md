# Infrastructure & Model Recommendation for Coding Agent

## 1. Environment Context
* **Instance:** AWS `g6e.4xlarge`
* **Hardware:** 1x NVIDIA L40S GPU (48 GB VRAM), 128 GB System RAM
* **Workload:** Background coding agent, low concurrency, large context requirements.

## 2. Inference Engine Selection: vLLM vs. Ollama vs. llama.cpp

### Recommended: vLLM
* **Why it wins here:** Cost efficiency and execution speed. When running a premium AWS instance, completing tasks faster allows you to spin down resources quicker or process more pipeline tasks per hour.
* **Hardware Utilization:** Fully saturates the enterprise L40S GPU for maximum tokens/second using AWQ or GPTQ quantization.
* **Feature Support:** Native, highly optimized support for Qwen3.6 Multi-Token Prediction (MTP), yielding 1.4x - 2.2x speedups.
* **Integration:** Exposes an OpenAI-compatible API seamlessly, which most agent frameworks (AutoGen, OpenHands, LangGraph) expect.

### Fallback: Ollama
* **Pros:** Extremely low friction. Installs as a native Linux daemon; zero Python/HuggingFace configuration required.
* **Cons:** Operates on `llama.cpp` under the hood. While easy to use, it often lags behind vLLM in cutting-edge optimizations (like MTP) and won't hit the absolute maximum hardware speed of the L40S.

### Not Recommended: llama.cpp (Standalone)
* **Reason:** Its primary strength is offloading model layers to system CPU RAM when GPU VRAM is insufficient. Since the recommended models fit entirely within your 48 GB VRAM, this feature is unnecessary, making the manual setup friction unrewarding.

---

## 3. Model Selection (Optimizing for 48GB VRAM)
For an autonomous coding agent, the context window (KV Cache) is critical. The model must leave enough VRAM leftover to ingest compiler logs, tool outputs, and multiple codebase files simultaneously without throwing Out-of-Memory (OOM) errors.

| Model | Quantization | VRAM for Weights | VRAM for KV Cache (Context) | Best For |
| :--- | :--- | :--- | :--- | :--- |
| **Qwen3.6-27B (Dense)** | 8-bit | ~27 GB | ~21 GB | **Overall Champion.** Exceptional repo-level coding and autonomous tool usage. Massive context room. |
| **QwQ-32B** | 8-bit | ~32 GB | ~16 GB | **Deep Reasoning.** Best for complex architectural design or logic-heavy debugging via Chain-of-Thought. |
| **Qwen3-Coder-Next 80B**| 4-bit (AWQ/GPTQ) | ~40 GB | ~8 GB | **Highly Agentic MoE.** Extremely capable, but strictly limits context window length. |
| **Gemma 3 (27B)** | 8-bit | ~27 GB | ~21 GB | **Multimodal Alternative.** Excellent if the agent needs to analyze screenshots or visual UI data. |

---

## 4. Final Execution Plan

**The optimal setup for your background coding agent:**
1.  **Engine:** Deploy **vLLM** (ideally via its official Docker container to keep the environment clean).
2.  **Model:** Pull **Qwen3.6-27B** (8-bit GPTQ or AWQ format) from Hugging Face.
3.  **Flags:** Ensure MTP (Multi-Token Prediction) speculative decoding flags are enabled in your vLLM startup command.
4.  **Connect:** Point your agent framework to `http://localhost:8000/v1` (vLLM's default OpenAI-compatible endpoint).