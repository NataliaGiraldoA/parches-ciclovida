"""Racha de domingos: cuántos seguidos lleva yendo a su parche."""

from datetime import date, timedelta

from fastapi.testclient import TestClient
from sqlmodel import Session

from app import services
from app.db import engine
from app.main import app
from app.models import Asignacion, Encuesta, Grupo, Jornada, Joven
from test_api import estado, nuevo, setup_function  # noqa: F401

D0 = date(2026, 8, 2)  # un domingo


def _domingos(session: Session, joven: Joven, fue: list[bool | None], confirmado: bool = False) -> None:
    """Un domingo terminado por semana. True/False: lo que dijo en la encuesta; None: no la respondió."""
    for i, asistio in enumerate(fue):
        fecha = D0 + timedelta(days=7 * i)
        session.add(Jornada(fecha=fecha, estado="finalizada"))
        g = Grupo(jornada_fecha=fecha, nombre=f"Parche {i}", tramo_id="metropolitana", segmento="mayor",
                  franja="08:00", actividad="bici")
        session.add(g)
        session.flush()
        session.add(Asignacion(grupo_id=g.id, joven_id=joven.id, jornada_fecha=fecha,
                               estado="confirmado" if confirmado else "pendiente"))
        if asistio is not None:
            session.add(Encuesta(joven_id=joven.id, jornada_fecha=fecha, grupo_id=g.id, asistio=asistio, volveria=True))
    session.commit()


def _joven(session: Session) -> Joven:
    j = Joven(nombre="Ana", correo_hash="x", universidad="univalle", rango_edad="18-22", comuna=20,
              actividad="bici", ritmo="moderado", acepta_datos=True)
    session.add(j)
    session.commit()
    return j


def test_racha_cuenta_domingos_seguidos_hasta_el_ultimo():
    with TestClient(app), Session(engine) as s:
        ana = _joven(s)
        _domingos(s, ana, [True, True, False, True, True, True])
        assert services.racha_para(s, ana) == {"actual": 3, "mejor": 3, "total": 5}


def test_racha_se_rompe_si_falto_el_ultimo_domingo():
    with TestClient(app), Session(engine) as s:
        ana = _joven(s)
        _domingos(s, ana, [True, True, False])
        assert services.racha_para(s, ana) == {"actual": 0, "mejor": 2, "total": 2}


def test_sin_encuesta_cuenta_si_habia_confirmado():
    with TestClient(app), Session(engine) as s:
        ana = _joven(s)
        _domingos(s, ana, [None, None], confirmado=True)
        assert services.racha_para(s, ana)["actual"] == 2
    with TestClient(app), Session(engine) as s:
        luis = Joven(nombre="Luis", correo_hash="y", universidad="univalle", rango_edad="18-22", comuna=20,
                     actividad="bici", ritmo="moderado", acepta_datos=True)
        s.add(luis)
        s.commit()
        assert services.racha_para(s, luis) == {"actual": 0, "mejor": 0, "total": 0}


def test_el_estado_trae_la_racha_y_el_clima_apagado_en_pruebas():
    with TestClient(app) as c:
        ana = nuevo(c, "Ana")
        e = estado(c, ana)
        assert e["racha"] == {"actual": 0, "mejor": 0, "total": 0}
        assert e["clima"] is None
