import hashlib
import json
import secrets
from pathlib import Path

import jwt
from cryptography.fernet import Fernet
from fastapi import Depends, HTTPException, Request
from pwdlib import PasswordHash
from sqlalchemy import select, text

from .config import get_settings
from .db import Merchant, SessionLocal, User, now

passwords = PasswordHash.recommended()


def local_secret(name):
    settings = get_settings()
    value = getattr(settings, name)
    if value:
        return value
    if settings.environment != "development":
        raise RuntimeError(f"{name.upper()} must be configured outside development")
    path = Path(".local") / name
    path.parent.mkdir(exist_ok=True)
    if not path.exists():
        value = Fernet.generate_key().decode() if name == "encryption_key" else secrets.token_urlsafe(48)
        try:
            with path.open("x") as file:
                file.write(value)
        except FileExistsError:
            pass
    return path.read_text().strip()


def encrypt(data):
    return Fernet(local_secret("encryption_key").encode()).encrypt(json.dumps(data).encode()).decode()


def decrypt(value):
    return (
        json.loads(Fernet(local_secret("encryption_key").encode()).decrypt(value.encode())) if value else {}
    )


def token(user):
    return jwt.encode(
        {"sub": user.id, "exp": now() + 28800, "iat": now(), "aud": "acg"},
        local_secret("secret_key"),
        algorithm="HS256",
    )


def get_db(request: Request):
    with SessionLocal() as db:
        if db.bind.dialect.name == "sqlite" and request.method not in ("GET", "HEAD", "OPTIONS"):
            db.execute(text("BEGIN IMMEDIATE"))
        try:
            yield db
            db.commit()
        except Exception:
            db.rollback()
            raise


def current_user(request: Request, db=Depends(get_db, scope="function")):
    header = request.headers.get("authorization", "")
    if not header.startswith("Bearer "):
        raise HTTPException(401, "Sign in to your workspace")
    try:
        payload = jwt.decode(header[7:], local_secret("secret_key"), algorithms=["HS256"], audience="acg")
        user = db.get(User, payload["sub"])
    except (jwt.PyJWTError, KeyError):
        raise HTTPException(401, "Session expired. Sign in again.") from None
    if not user:
        raise HTTPException(401, "Session is no longer valid")
    if request.method not in ("GET", "HEAD", "OPTIONS"):
        db.execute(select(Merchant).where(Merchant.id == user.merchant_id).with_for_update()).scalar_one()
    return user


def operator(user=Depends(current_user)):
    if user.role not in ("owner", "operator"):
        raise HTTPException(403, "An operator or owner is required")
    return user


def owner(user=Depends(current_user)):
    if user.role != "owner":
        raise HTTPException(403, "Only the workspace owner can perform this action")
    return user


def hash_key(key):
    return hashlib.sha256(key.encode()).hexdigest()
