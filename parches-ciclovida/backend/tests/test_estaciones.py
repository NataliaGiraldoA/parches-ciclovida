"""El catálogo de estaciones puede cambiar sin romper una base que ya existía."""

from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app import services
from app.catalog import ACTIVIDADES, FRANJAS, TRAMOS, tramo_info
from app.db import engine, init_db
from app.main import app
from app.models import Joven, Salida
from test_api import auth, nuevo


def test_parches_de_estaciones_retiradas_se_reemplazan():
    with TestClient(app) as c:
        c.get("/api/catalogo")
        with Session(engine) as s:
            j = services.jornada_abierta(s)
            # como una base de antes: un parche en una estación retirada y una estación nueva sin parches
            s.add(Salida(jornada_fecha=j.fecha, nombre="Parche Viejo", tramo_id="siloe", segmento="mayor",
                         franja="08:00", actividad="bici"))
            for x in s.exec(select(Salida).where(Salida.jornada_fecha == j.fecha, Salida.tramo_id == "dorada")).all():
                s.delete(x)
            s.commit()

            services.asegurar_parches(s, j.fecha)
            salidas = s.exec(select(Salida).where(Salida.jornada_fecha == j.fecha, Salida.segmento == "mayor")).all()
            assert {x.tramo_id for x in salidas} == {t["id"] for t in TRAMOS}
            assert len(salidas) == len(TRAMOS) * len(FRANJAS) * len(ACTIVIDADES)
    # los grupos viejos se siguen pudiendo leer
    assert tramo_info("siloe")["nombre"] == "Siloé"


def test_preferencia_en_estacion_retirada_pasa_a_su_reemplazo():
    with TestClient(app) as c:
        t = nuevo(c, "Iván", tramo_id="panamericana")
        with Session(engine) as s:
            joven = s.exec(select(Joven).where(Joven.token == t)).one()
            joven.tramo_id = "fortaleza"
            s.add(joven)
            s.commit()
        init_db()
        assert c.get("/api/yo", headers=auth(t)).json()["tramo_id"] == "san-carlos"
