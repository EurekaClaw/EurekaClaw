import numpy as np
from sentence_transformers import SentenceTransformer

_embedding_model: SentenceTransformer | None = None

def _load_embedding_model() -> SentenceTransformer:
    """Loads the SentenceTransformer model, lazy-loading it."""
    global _embedding_model
    if _embedding_model is None:
        # Using a small, fast model for lightweight RAG
        # This model is good for semantic similarity and runs locally.
        _embedding_model = SentenceTransformer('all-MiniLM-L6-v2')
    return _embedding_model

def get_embedding(text: str) -> list[float]:
    """Generates an embedding for the given text."""
    model = _load_embedding_model()
    embedding = model.encode(text, convert_to_tensor=False)
    return embedding.tolist()

def cosine_similarity(embedding1: list[float], embedding2: list[float]) -> float:
    """Calculates cosine similarity between two embeddings."""
    vec1 = np.array(embedding1)
    vec2 = np.array(embedding2)
    dot_product = np.dot(vec1, vec2)
    norm_a = np.linalg.norm(vec1)
    norm_b = np.linalg.norm(vec2)
    if norm_a == 0 or norm_b == 0:
        return 0.0  # Handle zero vectors gracefully
    return dot_product / (norm_a * norm_b)