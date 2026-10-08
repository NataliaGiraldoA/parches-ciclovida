import os
import sys
import tempfile
from pathlib import Path

_tmp = tempfile.mkdtemp()
os.environ["DATABASE_URL"] = f"sqlite:///{_tmp}/test.db"
os.environ["SCHEDULER"] = "0"
# Las pruebas nunca hablan con Telegram ni con Gemini de verdad, aunque backend/.env tenga las claves
# (config no pisa variables ya definidas).
os.environ["TELEGRAM_TOKEN"] = ""
os.environ["TELEGRAM_BOT"] = ""
os.environ["GEMINI_API_KEY"] = ""
os.environ["CLIMA"] = "0"
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
