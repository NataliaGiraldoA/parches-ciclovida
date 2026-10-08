"""Cómo se arman los grupos dentro de cada parche. Funciones puras: no tocan la base de datos.

El joven elige el parche (estación, hora y actividad). El sábado a las 5:00 p. m.:

1. Parches que no llegaron a 3 personas: cada quien se suma al parche compatible más
   parecido. Reglas que nunca se relajan: misma estación, menores nunca con mayores,
   a pie (caminar, trotar) nunca con sobre ruedas (bici, patines) y máximo 90 minutos
   de diferencia. Lo que cambió queda registrado para mostrárselo en la app.
2. Cada parche se parte en grupos de 3 a 6, lo más cerca posible de 5, con k-means de
   tamaño balanceado sobre estas variables, cada una normalizada de 0 a 1 y con su peso:
     * ritmo (tranquilo, moderado, rápido)                peso 1.0
     * rango de edad (18 a 22, 23 a 28)                   peso 0.6
     * experiencia (domingos que ya fue, hasta 3)         peso 0.4
     * quiz "Tu estilo de parche" (opcional)              peso 0.2 por pregunta (PESO_QUIZ)
       Cinco preguntas de gustos (plan después, charla, ruta nueva, esperar al
       grupo, madrugar), inspiradas en dimensiones clásicas de afinidad pero sin
       lenguaje clínico. Es solo un desempate: quien no lo responde queda en el
       punto medio y se agrupa igual por lo demás. Nunca se muestra a nadie.
   Así cada grupo queda con gente que disfruta el domingo de forma parecida.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Iterable

from . import config
from .catalog import ACTIVIDADES_POR_ID, FRANJA_ORDEN, RITMO_ORDEN, SEGMENTO_EDAD

# El quiz pesa menos que cualquier otra variable: es un desempate, no un filtro. Su peso se ajusta
# con PESO_QUIZ (config.py), midiendo el efecto con app/reporte.py.
PESOS = {"ritmo": 1.0, "edad": 0.6, "experiencia": 0.4, "quiz": config.PESO_QUIZ}
EDAD_ORDEN = {"14-17": 0, "18-22": 0, "23-28": 1}  # menores y mayores nunca comparten parche
EXPERIENCIA_MAX = 3

# Quien no responde el quiz queda en el punto medio: no lo acerca ni lo aleja de nadie.
QUIZ_NEUTRO = (0.5, 0.5, 0.5, 0.5, 0.5)


@dataclass(frozen=True)
class Participante:
    id: str
    tramo: str
    franja: str
    actividad: str
    ritmo: str
    rango_edad: str
    experiencia: int = 0
    # Las 5 respuestas del quiz "Tu estilo de parche" (0 a 1), o None si no lo respondió.
    quiz: tuple[float, ...] | None = None

    @property
    def segmento(self) -> str:
        return SEGMENTO_EDAD[self.rango_edad]

    @property
    def familia(self) -> str:
        return ACTIVIDADES_POR_ID[self.actividad]["familia"]

    @property
    def franja_orden(self) -> int:
        return FRANJA_ORDEN[self.franja]

    @property
    def ritmo_orden(self) -> int:
        return RITMO_ORDEN[self.ritmo]


@dataclass
class GrupoPropuesto:
    tramo: str
    segmento: str
    franja: str
    actividad: str
    ritmo: str
    miembros: list[Participante] = field(default_factory=list)

    @property
    def familia(self) -> str:
        return ACTIVIDADES_POR_ID[self.actividad]["familia"]

    def ajustes(self, p: Participante) -> list[str]:
        """Qué tuvo que ceder esta persona para entrar al grupo."""
        cambios = []
        if p.franja != self.franja:
            cambios.append("franja")
        if p.actividad != self.actividad:
            cambios.append("actividad")
        return cambios


def tamanos_balanceados(n: int, minimo: int, objetivo: int, maximo: int) -> list[int]:
    """Parte n personas en grupos entre `minimo` y `maximo`, lo más cerca de `objetivo`.

    Con empate prefiere menos grupos (más grandes aguantan mejor a quien no llega).
    """
    if n < minimo:
        return []
    k_min = math.ceil(n / maximo)
    k_max = max(k_min, n // minimo)
    k = min(range(k_min, k_max + 1), key=lambda k: (abs(n / k - objetivo), k))
    base, extra = divmod(n, k)
    return [base + 1] * extra + [base] * (k - extra)


# ---------------------------------------------------------------- k-means

Vector = tuple[float, ...]


def vector(p: Participante) -> Vector:
    """Ritmo, edad y experiencia primero; el quiz entra al final como desempate (peso 0,2)."""
    quiz = p.quiz or QUIZ_NEUTRO
    return (
        PESOS["ritmo"] * p.ritmo_orden / 2,
        PESOS["edad"] * EDAD_ORDEN[p.rango_edad],
        PESOS["experiencia"] * min(p.experiencia, EXPERIENCIA_MAX) / EXPERIENCIA_MAX,
        *(PESOS["quiz"] * x for x in quiz),
    )


def distancia2(a: Vector, b: Vector) -> float:
    return sum((x - y) ** 2 for x, y in zip(a, b))


def centroide(puntos: list[Vector]) -> Vector:
    return tuple(sum(c) / len(puntos) for c in zip(*puntos))  # type: ignore[return-value]


def _asignar_con_cupo(puntos: list[Vector], centros: list[Vector], tamanos: list[int]) -> list[int]:
    """Paso de asignación con cupo: los pares persona-centro más cercanos van primero."""
    pares = sorted((distancia2(p, c), i, j) for i, p in enumerate(puntos) for j, c in enumerate(centros))
    libres = list(tamanos)
    asignacion = [-1] * len(puntos)
    for _, i, j in pares:
        if asignacion[i] == -1 and libres[j] > 0:
            asignacion[i] = j
            libres[j] -= 1
    return asignacion


def kmeans_balanceado(participantes: Iterable[Participante], tamanos: list[int], iteraciones: int = 30) -> list[list[Participante]]:
    """K-means con el tamaño de cada grupo fijo. Determinista: mismo resultado con el mismo input."""
    gente = sorted(participantes, key=lambda p: (vector(p), p.id))
    k = len(tamanos)
    if sum(tamanos) != len(gente):
        raise ValueError("los tamaños no suman el total de personas")
    if k <= 1:
        return [gente] if gente else []
    puntos = [vector(p) for p in gente]
    # centros iniciales repartidos a lo largo de la gente ordenada: sin azar
    centros = [puntos[(2 * i + 1) * len(puntos) // (2 * k)] for i in range(k)]
    asignacion: list[int] = []
    for _ in range(iteraciones):
        nueva = _asignar_con_cupo(puntos, centros, tamanos)
        if nueva == asignacion:
            break
        asignacion = nueva
        centros = [centroide([puntos[i] for i, c in enumerate(asignacion) if c == j]) for j in range(k)]
    return [[gente[i] for i, c in enumerate(asignacion) if c == j] for j in range(k)]


def agrupar(participantes: Iterable[Participante], minimo: int = 3, objetivo: int = 5, maximo: int = 6) -> list[list[Participante]]:
    """Parte a la gente de un parche en grupos de `minimo` a `maximo`. Si no alcanzan, van juntos."""
    gente = list(participantes)
    tamanos = tamanos_balanceados(len(gente), minimo, objetivo, maximo) or ([len(gente)] if gente else [])
    return kmeans_balanceado(gente, tamanos)


def grupo_mas_cercano(p: Participante, grupos: list[list[Participante]], maximo: int) -> int | None:
    """Para quien se une después del sábado: el grupo con cupo cuyo centro está más cerca."""
    candidatos = [i for i, g in enumerate(grupos) if g and len(g) < maximo]
    if not candidatos:
        return None
    v = vector(p)
    return min(candidatos, key=lambda i: (distancia2(v, centroide([vector(m) for m in grupos[i]])), len(grupos[i]), i))


# ---------------------------------------------------------------- parches que no se llenaron

def puntaje(p: Participante, g: GrupoPropuesto) -> tuple:
    """Menor es mejor: primero la hora, luego la actividad, luego el ritmo, luego el tamaño."""
    return (
        abs(p.franja_orden - FRANJA_ORDEN[g.franja]),
        p.actividad != g.actividad,
        abs(p.ritmo_orden - RITMO_ORDEN[g.ritmo]),
        len(g.miembros),
    )


def compatible_basico(p: Participante, g: GrupoPropuesto) -> bool:
    """Reglas que nunca se relajan."""
    return p.tramo == g.tramo and p.segmento == g.segmento and p.familia == g.familia


def compatible_vecino(p: Participante, g: GrupoPropuesto) -> bool:
    return compatible_basico(p, g) and abs(p.franja_orden - FRANJA_ORDEN[g.franja]) <= 1


def mejor_grupo_para(p: Participante, grupos: list[GrupoPropuesto], maximo: int = 6) -> GrupoPropuesto | None:
    candidatos = [g for g in grupos if len(g.miembros) < maximo and compatible_vecino(p, g)]
    return min(candidatos, key=lambda g: puntaje(p, g)) if candidatos else None
