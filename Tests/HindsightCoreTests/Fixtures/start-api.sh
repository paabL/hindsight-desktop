#!/bin/bash
# Script de lancement fictif (fixture de test)
set -euo pipefail

export HINDSIGHT_API_LLM_PROVIDER=claude-code
export HINDSIGHT_API_LLM_MODEL="claude-sonnet-4-5"   # modèle principal
export HINDSIGHT_API_VLM_PROVIDER='gemini'
export HINDSIGHT_API_VLM_API_KEY="AIzaFAKEFAKEFAKEFAKE1234"
export HINDSIGHT_API_EMBEDDINGS_PROVIDER=gemini
export HINDSIGHT_API_EMBEDDINGS_GEMINI_OUTPUT_DIMENSIONALITY=1536
export HINDSIGHT_API_RERANKER_PROVIDER=cohere
export HINDSIGHT_API_RERANKER_COHERE_API_KEY="$COHERE_KEY"
export HINDSIGHT_API_LLM_MAX_CONCURRENT=4
HINDSIGHT_API_WORKER_MAX_SLOTS=2
export HINDSIGHT_API_LLM_MODEL=claude-sonnet-4-5-20250929
source ~/.hindsight/secrets.env

exec hindsight-api --port 8888
