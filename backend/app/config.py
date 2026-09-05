from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")
    database_url: str = "sqlite:///./gateway.db"
    redis_url: str = ""
    secret_key: str = ""
    encryption_key: str = ""
    nvidia_api_key: str = ""
    nvidia_base_url: str = "https://integrate.api.nvidia.com/v1"
    nvidia_model: str = "nvidia/nemotron-3-ultra-550b-a55b"
    nvidia_embedding_model: str = "nvidia/nv-embedqa-e5-v5"
    ai_timeout_seconds: float = 15
    razorpay_key_id: str = ""
    razorpay_key_secret: str = ""
    razorpay_webhook_secret: str = ""
    environment: str = "development"
    allowed_origins: str = "http://localhost:8080,http://127.0.0.1:8080"


@lru_cache
def get_settings():
    return Settings()
