import random
from collections import Counter

import pytest

from app.catalog import RITMOS
from app.matching import (
    GrupoPropuesto, Participante, agrupar, grupo_mas_cercano, kmeans_balanceado, mejor_grupo_para, tamanos_balanceados,
)


def P(i, tramo="panamericana", franja="08:00", actividad="bici", ritmo="moderado", edad="18-22", exp=0):
    return Participante(id=f"p{i:03d}", tramo=tramo, franja=franja, actividad=actividad, ritmo=ritmo,
                        rango_edad=edad, experiencia=exp)


def G(miembros, **kw):
    base = dict(tramo="panamericana", segmento="mayor", franja="08:00", actividad="bici", ritmo="moderado")
    base.update(kw)
    return GrupoPropuesto(miembros=list(miembros), **base)


@pytest.mark.parametrize("n,esperado", [
    (2, []), (3, [3]), (5, [5]), (6, [6]), (7, [4, 3]), (11, [6, 5]), (12, [6, 6]), (13, [5, 4, 4]),
])
def test_tamanos_balanceados(n, esperado):
    assert tamanos_balanceados(n, 3, 5, 6) == esperado


def test_kmeans_respeta_tamanos_y_no_pierde_a_nadie():
    rng = random.Random(7)
    gente = [P(i, ritmo=rng.choice(RITMOS)["id"], edad=rng.choice(["18-22", "23-28"]), exp=rng.randint(0, 5))
             for i in range(23)]
    grupos = agrupar(gente)
    assert sorted(len(g) for g in grupos) == sorted(tamanos_balanceados(23, 3, 5, 6))
    assert Counter(p.id for g in grupos for p in g) == Counter(p.id for p in gente)


def test_kmeans_junta_ritmos_parecidos():
    gente = [P(i, ritmo="tranquilo") for i in range(5)] + [P(i + 5, ritmo="rapido") for i in range(5)]
    grupos = kmeans_balanceado(gente, [5, 5])
    for g in grupos:
        assert len({p.ritmo for p in g}) == 1


def test_kmeans_usa_edad_y_experiencia_cuando_el_ritmo_empata():
    gente = ([P(i, edad="18-22", exp=0) for i in range(4)] + [P(i + 4, edad="23-28", exp=3) for i in range(4)])
    grupos = kmeans_balanceado(gente, [4, 4])
    for g in grupos:
        assert len({(p.rango_edad, p.experiencia) for p in g}) == 1


def test_kmeans_es_determinista():
    rng = random.Random(3)
    gente = [P(i, ritmo=rng.choice(RITMOS)["id"], exp=rng.randint(0, 3)) for i in range(17)]
    a = agrupar(gente)
    b = agrupar(list(reversed(gente)))
    assert [[p.id for p in g] for g in a] == [[p.id for p in g] for g in b]


def test_kmeans_desempata_con_el_quiz():
    """Con todo lo demás igual, el quiz junta a quienes disfrutan el domingo parecido."""
    sociables = [P(i) for i in range(3)]
    caseros = [P(i + 3) for i in range(3)]
    sociables = [Participante(**{**p.__dict__, "quiz": (1.0, 1.0, 1.0, 1.0, 1.0)}) for p in sociables]
    caseros = [Participante(**{**p.__dict__, "quiz": (0.0, 0.0, 0.0, 0.0, 0.0)}) for p in caseros]
    grupos = kmeans_balanceado(sociables + caseros, [3, 3])
    for g in grupos:
        assert len({p.quiz for p in g}) == 1


def test_el_ritmo_manda_sobre_el_quiz():
    """El quiz es secundario: nunca le gana a una variable estructural como el ritmo."""
    gente = [
        Participante(**{**P(1).__dict__, "ritmo": "tranquilo", "quiz": (1.0,) * 5}),
        Participante(**{**P(2).__dict__, "ritmo": "tranquilo", "quiz": (0.0,) * 5}),
        Participante(**{**P(3).__dict__, "ritmo": "rapido", "quiz": (1.0,) * 5}),
        Participante(**{**P(4).__dict__, "ritmo": "rapido", "quiz": (0.0,) * 5}),
    ]
    grupos = kmeans_balanceado(gente, [2, 2])
    for g in grupos:
        assert len({p.ritmo for p in g}) == 1


def test_sin_quiz_queda_neutro_y_agrupa_igual():
    gente = [P(i) for i in range(6)]  # nadie respondió el quiz
    assert sorted(len(g) for g in agrupar(gente)) == [6]


def test_si_no_alcanza_el_minimo_van_juntos():
    assert [len(g) for g in agrupar([P(1), P(2)])] == [2]
    assert agrupar([]) == []


def test_tarde_entra_al_grupo_mas_parecido_con_cupo():
    tranquilos = [P(i, ritmo="tranquilo") for i in range(4)]
    rapidos = [P(i + 4, ritmo="rapido") for i in range(4)]
    assert grupo_mas_cercano(P(50, ritmo="rapido"), [tranquilos, rapidos], maximo=6) == 1
    llenos = [tranquilos + [P(60), P(61)], rapidos + [P(62), P(63)]]
    assert grupo_mas_cercano(P(51), llenos, maximo=6) is None


def test_reglas_que_nunca_se_relajan_al_juntar_parches():
    destino = G([P(1), P(2), P(3)])
    assert mejor_grupo_para(P(9, actividad="patines", franja="09:30"), [destino]) is destino
    assert mejor_grupo_para(P(9, tramo="metropolitana"), [destino]) is None
    assert mejor_grupo_para(P(9, actividad="caminar"), [destino]) is None  # a pie no va con ruedas
    assert mejor_grupo_para(P(9, franja="11:00"), [destino]) is None  # más de 90 minutos
    assert mejor_grupo_para(P(9, edad="14-17"), [destino]) is None  # menores nunca con mayores


def test_prefiere_la_misma_hora_y_actividad():
    misma = G([P(1), P(2)], franja="09:30", actividad="bici")
    otra = G([P(3), P(4)], franja="08:00", actividad="patines")
    assert mejor_grupo_para(P(9, franja="09:30"), [otra, misma]) is misma
