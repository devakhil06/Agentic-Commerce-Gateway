"""Create a private production secret environment file without printing credentials."""
import secrets
from pathlib import Path
from cryptography.fernet import Fernet

target = Path('.env.production')
with target.open('x') as file:
    file.write('ENVIRONMENT=production\n')
    file.write('SECRET_KEY='+secrets.token_urlsafe(48)+'\n')
    file.write('ENCRYPTION_KEY='+Fernet.generate_key().decode()+'\n')
    file.write('POSTGRES_PASSWORD='+secrets.token_urlsafe(32)+'\n')
    file.write('NVIDIA_API_KEY=\n')
    file.write('ALLOWED_ORIGINS=http://localhost:8000\n')
print('Created .env.production. Add the NVIDIA key and production HTTPS origin before deployment.')
