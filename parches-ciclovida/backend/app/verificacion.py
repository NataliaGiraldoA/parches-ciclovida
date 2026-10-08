"""Filtro de confianza: solo estudiantes con correo institucional de una universidad de Cali.

El correo nunca se guarda. Se guarda su huella HMAC (para que un correo no abra dos cuentas)
y la universidad. El código de 6 dígitos vence en CODIGO_MINUTOS y admite 5 intentos.
"""

from __future__ import annotations

import hashlib
import hmac
import logging
import re
import secrets
import smtplib
from datetime import timedelta
from email.message import EmailMessage

from sqlmodel import Session, select

from . import config
from .catalog import universidad_de
from .models import Joven, Verificacion

log = logging.getLogger("parches")
CORREO_RE = re.compile(r"^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$")
MAX_INTENTOS = 5


class CorreoInvalido(ValueError):
    pass


def normalizar(correo: str) -> str:
    return correo.strip().lower()


def huella(texto: str) -> str:
    return hmac.new(config.SECRETO.encode(), texto.encode(), hashlib.sha256).hexdigest()


def universidad_valida(correo: str) -> dict:
    correo = normalizar(correo)
    if not CORREO_RE.match(correo):
        raise CorreoInvalido("Escribe un correo válido")
    uni = universidad_de(correo)
    if uni is None:
        raise CorreoInvalido("Usa el correo institucional de tu universidad (por ejemplo, @usbcali.edu.co)")
    return uni


def solicitar(session: Session, correo: str, ahora, para: str = "registro") -> dict:
    """Envía el código. `para` es "registro" (cuenta nueva) o "ingreso" (volver a entrar)."""
    uni = universidad_valida(correo)
    correo = normalizar(correo)
    h = huella(correo)
    existe = session.exec(select(Joven.id).where(Joven.correo_hash == h)).first() is not None
    if para == "registro" and existe:
        raise LookupError("Ese correo ya tiene una cuenta. Toca «Ya tengo cuenta» para entrar.")
    if para == "ingreso" and not existe:
        raise LookupError("Ese correo aún no tiene cuenta. Crea tu perfil primero.")
    if not config.SMTP_HOST and not config.CORREO_DEMO:
        raise RuntimeError("El envío de correos no está configurado")
    codigo = f"{secrets.randbelow(10**6):06d}"
    v = session.get(Verificacion, h) or Verificacion(correo_hash=h, codigo_hash="", expira=ahora)
    v.codigo_hash = huella(f"{h}:{codigo}")
    v.expira = ahora + timedelta(minutes=config.CODIGO_MINUTOS)
    v.intentos = 0
    session.add(v)
    session.commit()
    salida = {"universidad": uni["nombre"], "minutos": config.CODIGO_MINUTOS}
    if config.SMTP_HOST:
        _enviar(correo, codigo)
    else:
        log.info("Código de demostración para %s: %s", uni["corto"], codigo)
        salida["codigo_demo"] = codigo
    return salida


def comprobar(session: Session, correo: str, codigo: str, ahora) -> tuple[dict, str]:
    """Devuelve la universidad y la huella del correo si el código es correcto."""
    uni = universidad_valida(correo)
    h = huella(normalizar(correo))
    v = session.get(Verificacion, h)
    if v is None or v.expira < ahora:
        raise CorreoInvalido("El código venció o no existe. Pide uno nuevo.")
    if v.intentos >= MAX_INTENTOS:
        raise CorreoInvalido("Hiciste demasiados intentos. Pide un código nuevo.")
    if not hmac.compare_digest(v.codigo_hash, huella(f"{h}:{codigo.strip()}")):
        v.intentos += 1
        session.add(v)
        session.commit()
        raise CorreoInvalido("El código no coincide. Revisa el correo que te enviamos.")
    session.delete(v)
    return uni, h


def _enviar(correo: str, codigo: str) -> None:
    msg = EmailMessage()
    msg["Subject"] = f"Tu código de Parches CicloVida: {codigo}"
    msg["From"] = config.SMTP_FROM
    msg["To"] = correo
    msg.set_content(
        f"Tu código para entrar a Parches CicloVida es {codigo}.\n"
        f"Vence en {config.CODIGO_MINUTOS} minutos. Si no lo pediste, ignora este correo."
    )
    with smtplib.SMTP(config.SMTP_HOST, config.SMTP_PORT, timeout=15) as s:
        s.starttls()
        if config.SMTP_USER:
            s.login(config.SMTP_USER, config.SMTP_PASS)
        s.send_message(msg)
