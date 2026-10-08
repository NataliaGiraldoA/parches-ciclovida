from itertools import count

from fastapi.testclient import TestClient
from sqlmodel import SQLModel

from app.db import engine
from app.main import app

ADMIN = {"X-Admin-Key": "dedsec-demo"}
_n = count()


def registro(nombre, **kw):
    base = dict(nombre=nombre, rango_edad="18-22", comuna=19, tramo_id="panamericana",
                actividad="bici", ritmo="moderado", acepta_datos=True, declara_mayor=True)
    base.update(kw)
    return base


def auth(tok):
    return {"Authorization": f"Bearer {tok}"}


def codigo(c, correo):
    r = c.post("/api/verificacion", json={"correo": correo})
    assert r.status_code == 200, r.text
    return r.json()["codigo_demo"]


def nuevo(c, nombre, correo=None, **kw):
    correo = correo or f"estudiante{next(_n)}@usbcali.edu.co"
    r = c.post("/api/jovenes", json=registro(nombre, correo=correo, codigo=codigo(c, correo), **kw))
    assert r.status_code == 201, r.text
    return r.json()["token"]


def parche(c, tok, tramo="panamericana", franja="08:00", actividad="bici"):
    lista = c.get("/api/parches", params={"tramo": tramo, "franja": franja, "actividad": actividad},
                  headers=auth(tok)).json()["parches"]
    return lista[0]


def unir(c, tok, parche_id):
    return c.post("/api/yo/parche", json={"parche_id": parche_id}, headers=auth(tok))


def estado(c, tok):
    return c.get("/api/yo/parche", headers=auth(tok)).json()


def armar(c):
    r = c.post("/api/admin/armar-grupos", headers=ADMIN)
    assert r.status_code == 200, r.text
    return r.json()


def setup_function():
    SQLModel.metadata.drop_all(engine)


def test_flujo_completo_domingo():
    with TestClient(app) as c:
        cat = c.get("/api/catalogo").json()
        assert len(cat["tramos"]) == 11 and len(cat["comunas"]) == 22 and len(cat["universidades"]) >= 5

        tokens = [nuevo(c, n) for n in ["ana maría", "Luis", "Sara", "Kevin", "Paula"]]
        yo = c.get("/api/yo", headers=auth(tokens[0])).json()
        assert yo["nombre"] == "Ana" and yo["universidad"] == "Universidad de San Buenaventura Cali"
        assert estado(c, tokens[0])["estado"] == "sin_parche"

        # el sistema ya generó un parche por hora y actividad en cada estación
        lista = c.get("/api/parches", params={"tramo": "panamericana"}, headers=auth(tokens[0])).json()["parches"]
        assert len(lista) == 12
        assert sum(p["para_ti"] for p in lista) == 3  # bici en Panamericana, a las tres horas
        assert "miembros" not in lista[0]  # la lista no muestra nombres

        p0 = parche(c, tokens[0])
        for t in tokens:
            assert unir(c, t, p0["id"]).status_code == 200
        mio = parche(c, tokens[0])
        assert mio["id"] == p0["id"] and mio["inscritos"] == 5 and mio["es_mio"]

        e = estado(c, tokens[0])
        assert e["estado"] == "inscrito" and e["salida"]["inscritos"] == 5 and e["grupo"] is None
        # antes del sábado no hay grupo que confirmar
        assert c.post("/api/yo/parche/respuesta", json={"va": True}, headers=auth(tokens[0])).status_code == 409

        res = armar(c)
        assert res["grupos"] == 1 and res["emparejados"] == 5 and res["movidos"] == 0

        e = estado(c, tokens[0])
        assert e["estado"] == "asignado" and e["mi_respuesta"] == "pendiente"
        g = e["grupo"]
        assert g["punto_encuentro"] == "Calle 9 con Carrera 37A" and g["hora_encuentro"] == "08:00"
        assert g["miembros"][0]["soy_yo"] and len(g["miembros"]) == 5
        assert set(g["miembros"][0]) == {"ref", "nombre", "universidad", "actividad", "estado", "soy_yo"}
        assert g["miembros"][0]["universidad"] == "USB Cali"

        e = c.post("/api/yo/parche/respuesta", json={"va": True}, headers=auth(tokens[0])).json()
        assert e["mi_respuesta"] == "confirmado" and e["grupo"]["confirmados"] == 1

        # quien llega después del sábado entra al grupo con cupo; si está lleno, se abre otro
        sexto = nuevo(c, "Tomás")
        e6 = unir(c, sexto, p0["id"]).json()
        assert e6["tarde"] is True and e6["grupo"]["id"] == g["id"] and len(e6["grupo"]["miembros"]) == 6
        septimo = nuevo(c, "Juan")
        e7 = unir(c, septimo, p0["id"]).json()
        assert e7["grupo"]["id"] != g["id"] and e7["grupo"]["nombre"].endswith(" B")
        assert estado(c, tokens[0])["grupo"]["nombre"].endswith(" A")

        # la encuesta no existe antes de que termine la jornada
        assert c.post("/api/yo/encuesta", json={"asistio": True, "volveria": True, "bienestar": 4},
                      headers=auth(tokens[0])).status_code == 409

        fin = c.post("/api/admin/finalizar", headers=ADMIN).json()
        e = estado(c, tokens[0])
        assert e["encuesta"]["jornada_fecha"] == fin["finalizada"] and not e["encuesta"]["respondida"]
        assert e["jornada"]["fecha"] == fin["siguiente"] and e["estado"] == "sin_parche"

        for i, t in enumerate(tokens):
            r = c.post("/api/yo/encuesta", json={"asistio": i != 4, "volveria": True, "bienestar": 4 if i != 4 else None},
                       headers=auth(t))
            assert r.status_code == 200, r.text
        assert estado(c, tokens[0])["encuesta"]["respondida"]

        tab = c.get("/api/tablero/resumen", params={"fecha": fin["finalizada"]}).json()
        assert tab["kpis"]["emparejados"] == 7 and tab["kpis"]["parches"] == 2 and tab["kpis"]["respuestas"] == 5
        assert tab["kpis"]["asistencia_pct"] == 80.0 and tab["kpis"]["bienestar_promedio"] == 4.0
        comuna19 = next(r for r in tab["por_comuna"] if r["comuna"] == 19)
        assert comuna19["inscritos"] == {"valor": 7, "suprimido": False}
        texto = str(tab)
        assert "Ana" not in texto and "Kevin" not in texto  # el tablero no expone personas


def test_correo_institucional():
    with TestClient(app) as c:
        r = c.post("/api/verificacion", json={"correo": "ana@gmail.com"})
        assert r.status_code == 422 and "institucional" in r.text
        # los subdominios de estudiantes también cuentan
        assert c.post("/api/verificacion", json={"correo": "ana@u.icesi.edu.co"}).json()["universidad"] == "Universidad Icesi"

        correo = "Ana.Perez@UAO.edu.co"
        cod = codigo(c, correo)
        malo = "000000" if cod != "000000" else "111111"
        r = c.post("/api/jovenes", json=registro("Ana", correo=correo, codigo=malo))
        assert r.status_code == 422 and "no coincide" in r.text
        # registrarse sin verificar no se puede, aunque el dominio sea válido
        r = c.post("/api/jovenes", json=registro("Beto", correo="beto@uao.edu.co", codigo="123456"))
        assert r.status_code == 422
        # con otro dominio el formulario ni siquiera pasa
        assert c.post("/api/jovenes", json=registro("Beto", correo="beto@hotmail.com", codigo="123456")).status_code == 422

        tok = c.post("/api/jovenes", json=registro("Ana", correo=correo, codigo=cod)).json()["token"]
        assert c.get("/api/yo", headers=auth(tok)).json()["universidad"] == "Universidad Autónoma de Occidente"
        # el código ya se usó, y el mismo correo no abre otra cuenta
        assert c.post("/api/jovenes", json=registro("Ana", correo=correo, codigo=cod)).status_code == 422
        r = c.post("/api/verificacion", json={"correo": "ana.perez@uao.edu.co"})
        assert r.status_code == 409


def test_codigo_con_intentos_limitados():
    with TestClient(app) as c:
        correo = "ana@usc.edu.co"
        cod = codigo(c, correo)
        malo = "000000" if cod != "000000" else "111111"
        for _ in range(5):
            c.post("/api/jovenes", json=registro("Ana", correo=correo, codigo=malo))
        r = c.post("/api/jovenes", json=registro("Ana", correo=correo, codigo=cod))
        assert r.status_code == 422 and "intentos" in r.text


def test_kmeans_separa_por_ritmo():
    with TestClient(app) as c:
        toks = [nuevo(c, f"T{i}", ritmo="tranquilo") for i in range(6)] + [nuevo(c, f"R{i}", ritmo="rapido") for i in range(6)]
        p0 = parche(c, toks[0])
        for t in toks:
            unir(c, t, p0["id"])
        assert armar(c)["grupos"] == 2
        for t in toks:
            g = estado(c, t)["grupo"]
            assert len(g["miembros"]) == 6
            assert len({m["nombre"][0] for m in g["miembros"]}) == 1  # todos T o todos R


def test_parche_pequeno_se_junta_con_uno_compatible():
    with TestClient(app) as c:
        solo = nuevo(c, "Ana")
        unir(c, solo, parche(c, solo)["id"])  # 8:00 bici
        otros = [nuevo(c, n) for n in ["Beto", "Caro", "Dani"]]
        destino = parche(c, otros[0], franja="09:30", actividad="patines")
        for t in otros:
            unir(c, t, destino["id"])
        lejos = nuevo(c, "Eva", tramo_id="metropolitana")
        unir(c, lejos, parche(c, lejos, tramo="metropolitana", actividad="caminar")["id"])

        r = armar(c)
        assert r["movidos"] == 1 and r["solos"] == 1 and r["grupos"] == 2

        e = estado(c, solo)
        assert e["grupo"]["hora_encuentro"] == "09:30" and len(e["grupo"]["miembros"]) == 4
        assert sorted(e["ajustes"]) == ["actividad", "franja"]
        # en Metropolitana no había nadie compatible: va con su parche, así sea sola
        assert estado(c, lejos)["estado"] == "asignado"


def test_cambiar_de_parche_y_salir():
    with TestClient(app) as c:
        t = nuevo(c, "Ana")
        a, b = parche(c, t), parche(c, t, franja="09:30")
        unir(c, t, a["id"])
        e = unir(c, t, b["id"]).json()
        assert e["salida"]["id"] == b["id"] and parche(c, t)["inscritos"] == 0
        assert c.delete("/api/yo/parche", headers=auth(t)).json()["estado"] == "sin_parche"


def test_supresion_de_conteos_pequenos():
    with TestClient(app) as c:
        for n in ["Uno", "Dos"]:
            t = nuevo(c, n, comuna=3)
            unir(c, t, parche(c, t)["id"])
        armar(c)
        tab = c.get("/api/tablero/resumen").json()
        comuna3 = next(r for r in tab["por_comuna"] if r["comuna"] == 3)
        assert comuna3["inscritos"] == {"valor": None, "suprimido": True}


def test_validaciones_y_permisos():
    with TestClient(app) as c:
        correo = "val@usbcali.edu.co"
        cod = codigo(c, correo)
        assert c.post("/api/jovenes", json=registro("Ana", correo=correo, codigo=cod, acepta_datos=False)).status_code == 422
        assert c.post("/api/jovenes", json=registro("Ana", correo=correo, codigo=cod, tramo_id="luna")).status_code == 422
        # por defecto el piloto es solo para mayores de 18
        assert [r["id"] for r in c.get("/api/catalogo").json()["rangos_edad"]] == ["18-22", "23-28"]
        r = c.post("/api/jovenes", json=registro("Ana", correo=correo, codigo=cod, rango_edad="14-17",
                                                 permiso_acudiente=True, acudiente_nombre="Rosa"))
        assert r.status_code == 422 and "18 a 28" in r.text
        # la estación favorita es opcional: solo sirve para recomendar
        tok = c.post("/api/jovenes", json=registro("Ana", correo=correo, codigo=cod, tramo_id=None)).json()["token"]
        aviso = c.get("/api/aviso-privacidad").json()
        assert aviso["version"] and any("Tus derechos" == s["titulo"] for s in aviso["secciones"])
        assert c.get("/api/yo/parche").status_code == 401
        assert c.get("/api/parches").status_code == 401
        assert c.post("/api/admin/armar-grupos").status_code == 403
        assert unir(c, tok, 999999).status_code == 409


def test_pausa_y_borrado():
    with TestClient(app) as c:
        t = nuevo(c, "Ana")
        unir(c, t, parche(c, t)["id"])
        r = c.patch("/api/yo", json={"pausar_esta_semana": True}, headers=auth(t)).json()
        assert r["pausa_fecha"] is not None
        assert estado(c, t)["estado"] == "pausado"
        assert parche(c, t)["inscritos"] == 0  # pausar la saca del parche

        # unirse de nuevo quita la pausa
        assert unir(c, t, parche(c, t)["id"]).json()["estado"] == "inscrito"

        # cambiar preferencias no la saca del parche que eligió
        c.patch("/api/yo", json={"tramo_id": "metropolitana"}, headers=auth(t))
        assert estado(c, t)["estado"] == "inscrito"

        assert c.delete("/api/yo", headers=auth(t)).status_code == 204
        assert c.get("/api/yo", headers=auth(t)).status_code == 401


def test_seed_y_tablero():
    from app.seed import sembrar

    info = sembrar(total=180, semanas=4, reset=True)
    with TestClient(app) as c:
        tab = c.get("/api/tablero/resumen").json()
        assert tab["datos_sinteticos"] is True
        assert tab["estado"] == "finalizada" and len(tab["tendencia"]) == 4
        assert tab["kpis"]["parches"] > 10
        assert all(2 <= g["tamano"] <= 6 or g["tamano"] == 1 for g in tab["por_grupo"])
        assert c.get("/api/tablero/jornadas").json()[0]["fecha"] == info["proxima"]
        assert c.get("/tablero/").status_code == 200
        # la lista del próximo domingo ya tiene gente
        t = nuevo(c, "Ana")
        assert any(p["inscritos"] > 0 for p in c.get("/api/parches", headers=auth(t)).json()["parches"])


def test_menores_con_acudiente_y_parches_aparte(monkeypatch):
    from app import config

    monkeypatch.setattr(config, "PERMITIR_MENORES", True)
    with TestClient(app) as c:
        assert "14-17" in [r["id"] for r in c.get("/api/catalogo").json()["rangos_edad"]]
        correo = "menor@usc.edu.co"
        cod = codigo(c, correo)
        r = c.post("/api/jovenes", json=registro("Ana", correo=correo, codigo=cod, rango_edad="14-17", permiso_acudiente=True))
        assert r.status_code == 422
        menor = nuevo(c, "Ana", rango_edad="14-17", permiso_acudiente=True, acudiente_nombre="Rosa Pérez")
        adulto = nuevo(c, "Beto")
        de_adultos = parche(c, adulto)
        assert de_adultos["id"] != parche(c, menor)["id"]
        r = unir(c, menor, de_adultos["id"])
        assert r.status_code == 409 and "grupo de edad" in r.text


def test_encuesta_sin_bienestar_es_valida():
    with TestClient(app) as c:
        toks = [nuevo(c, n) for n in ["Uno", "Dos", "Tres"]]
        for t in toks:
            unir(c, t, parche(c, t)["id"])
        armar(c)
        c.post("/api/admin/finalizar", headers=ADMIN)
        r = c.post("/api/yo/encuesta", json={"asistio": True, "volveria": True}, headers=auth(toks[0]))
        assert r.status_code == 200 and r.json()["encuesta"]["respondida"]


def test_reportes_suspenden_y_no_llegan_al_tablero():
    with TestClient(app) as c:
        toks = [nuevo(c, n) for n in ["Ana", "Beto", "Caro", "Dani"]]
        p0 = parche(c, toks[0])
        for t in toks:
            unir(c, t, p0["id"])
        armar(c)
        g = estado(c, toks[0])["grupo"]
        dani = next(m for m in g["miembros"] if m["nombre"] == "Dani")

        # no se puede reportar un grupo ajeno ni a alguien de otro grupo
        assert c.post("/api/yo/reportes", json={"grupo_id": 999, "motivo": "riesgo"}, headers=auth(toks[0])).status_code == 409
        assert c.post("/api/yo/reportes", json={"grupo_id": g["id"], "motivo": "inventado"}, headers=auth(toks[0])).status_code == 422

        r = c.post("/api/yo/reportes", json={"grupo_id": g["id"], "ref": dani["ref"], "motivo": "acoso", "detalle": "x"},
                   headers=auth(toks[0]))
        assert r.status_code == 201
        # un solo reporte no suspende; el mismo denunciante repetido tampoco cuenta doble
        c.post("/api/yo/reportes", json={"grupo_id": g["id"], "ref": dani["ref"], "motivo": "acoso"}, headers=auth(toks[0]))
        assert estado(c, toks[3])["estado"] == "asignado"

        c.post("/api/yo/reportes", json={"grupo_id": g["id"], "ref": dani["ref"], "motivo": "riesgo"}, headers=auth(toks[1]))
        assert estado(c, toks[3])["estado"] == "suspendido"
        assert "Dani" not in [m["nombre"] for m in estado(c, toks[0])["grupo"]["miembros"]]
        assert unir(c, toks[3], p0["id"]).status_code == 409  # suspendida no puede volver a unirse

        cola = c.get("/api/admin/reportes", headers=ADMIN).json()
        assert len(cola) == 3 and cola[0]["reportado"]["suspendido"]
        assert c.get("/api/admin/reportes").status_code == 403

        tab = c.get("/api/tablero/resumen", params={"fecha": c.get("/api/tablero/jornadas").json()[0]["fecha"]}).json()
        assert tab["kpis"]["reportes"] == 3 and "Dani" not in str(tab)

        # moderación revisa y reactiva
        c.post(f"/api/admin/reportes/{cola[0]['id']}/revisar", params={"reactivar": True}, headers=ADMIN)
        assert estado(c, toks[3])["estado"] != "suspendido"

        # si quien reportó borra su cuenta, el reporte se conserva sin vínculo
        assert c.delete("/api/yo", headers=auth(toks[0])).status_code == 204
        assert len(c.get("/api/admin/reportes", params={"pendientes": False}, headers=ADMIN).json()) == 3
