"""Entrada serverless de Vercel para la API FastAPI."""

from pathlib import Path
import sys

BACKEND = Path(__file__).resolve().parents[1] / "parches-ciclovida" / "backend"
sys.path.insert(0, str(BACKEND))

from app.main import app  # noqa: E402
