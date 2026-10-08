# Reporte del emparejamiento · domingo 20 de septiembre de 2026

> Solo se muestran el estilo de parche y el perfil de los jóvenes simulados. De las personas reales no se exporta ni el nombre ni las respuestas del quiz. No es para el tablero. Generado con `python -m app.reporte`.

## Resumen

| | |
|---|---|
| Personas con grupo | 1.217 |
| Grupos | 257 |
| En grupos de 3 a 6 | 100,0 % |
| Solos / grupos de 2 | 0 / 0 |
| Cambiaron de hora o actividad para completar grupo | 22 |
| Respondieron el quiz (simulados) | 858 |

| Actividad | Personas | En grupos de 3 o más |
|---|---|---|
| Bici | 473 | 100,0 % |
| Caminar | 390 | 100,0 % |
| Patines | 171 | 100,0 % |
| Trotar | 183 | 100,0 % |

## ¿Sirve el quiz?

k-means dividió **78 parches** (1.035 personas). Al quitar el quiz, a **288** de ellas les cambia el grupo.

| Grupos armados… | Afinidad de estilo | Mismo ritmo |
|---|---|---|
| con el quiz (como funciona la app) | **66,0 %** | **81,4 %** |
| sin el quiz | 64,1 % | 81,2 % |
| al azar | 61,2 % | 60,9 % |

Pesos de k-means: ritmo 1,0, edad 0,6, experiencia 0,4 y quiz 0,2 por pregunta (se cambia con `PESO_QUIZ`).

_Solo cuenta los parches que k-means dividió (7 personas o más; con 3 a 6 queda un solo grupo). Afinidad de estilo: entre los simulados que respondieron el quiz, qué parte de cada grupo comparte el perfil más común del grupo. Mismo ritmo: qué parte de cada grupo va al ritmo más común del grupo. Se compara con armar los mismos grupos sin el quiz y al azar (promedio de 30 sorteos)._

## Ejemplos: grupos de parches que k-means dividió (primeros 6)

### Parche Chiminango A · San Carlos · 11:00 a. m. · Bici (6 personas)

- Mismo parche: estación San Carlos, 11:00 a. m., bici.
- Ritmo: 5 de 6 van a ritmo tranquilo.
- Edad: todos entre 18 y 22 años.
- Experiencia: de 0 a 1 domingos con parche.
- Estilo, entre quienes respondieron el quiz: «Foto del grupo y a la casa» (4 de 5); «En mi mundo, gozándome el paisaje» (4 de 5); «Llegando justo con la salida» (4 de 5).

| Integrante | Perfil (simulado) | Ritmo | Edad | Domingos | Quiz 1 a 5 | Distancia al centro |
|---|---|---|---|---|---|---|
| Gabriela | Contemplativo | tranquilo | 18 a 22 | 0 | b·b·a·a·b | 0,24 |
| Santiago | Contemplativo | tranquilo | 18 a 22 | 0 | b·b·a·a·b | 0,24 |
| Samuel | Contemplativo | tranquilo | 18 a 22 | 0 | b·b·b·b·b | 0,24 |
| Mateo | Contemplativo | tranquilo | 18 a 22 | 0 | — | 0,19 |
| Alejandro | Parchadito social | tranquilo | 18 a 22 | 1 | a·a·b·a·b | 0,32 |
| Nicolás | Deportista | rápido | 18 a 22 | 0 | b·b·b·b·a | 0,86 |

### Parche Chiminango B · San Carlos · 11:00 a. m. · Bici (5 personas)

- Mismo parche: estación San Carlos, 11:00 a. m., bici.
- Ritmo: 3 de 5 van a ritmo moderado.
- Edad: todos entre 23 y 28 años.
- Experiencia: de 0 a 2 domingos con parche.
- Estilo, entre quienes respondieron el quiz: «Paramos todos: nadie se queda» (4 de 4); «¡Jugo y charla con el parche!» (3 de 4); «Echando cuento todo el camino» (3 de 4).

| Integrante | Perfil (simulado) | Ritmo | Edad | Domingos | Quiz 1 a 5 | Distancia al centro |
|---|---|---|---|---|---|---|
| Laura | Parchadito social | tranquilo | 23 a 28 | 2 | a·a·a·a·b | 0,53 |
| Vanessa | Parchadito social | moderado | 23 a 28 | 0 | a·a·b·a·a | 0,27 |
| Andrés | Contemplativo | moderado | 23 a 28 | 1 | b·b·a·a·b | 0,22 |
| Sebastián | Contemplativo | moderado | 23 a 28 | 2 | — | 0,15 |
| Luisa | Parchadito social | rápido | 23 a 28 | 1 | a·a·a·a·b | 0,52 |

### Parche Samán A · Ciudad de Cali · 9:30 a. m. · Caminar (5 personas)

- Mismo parche: estación Ciudad de Cali, 9:30 a. m., caminar.
- Ritmo: 4 de 5 van a ritmo tranquilo.
- Edad: 3 de 5 entre 23 y 28 años.
- Experiencia: de 0 a 2 domingos con parche.
- Estilo, entre quienes respondieron el quiz: «En mi mundo, gozándome el paisaje» (4 de 4); «Llegando justo con la salida» (4 de 4); «Foto del grupo y a la casa» (3 de 4).

| Integrante | Perfil (simulado) | Ritmo | Edad | Domingos | Quiz 1 a 5 | Distancia al centro |
|---|---|---|---|---|---|---|
| Luisa | Parchadito social | tranquilo | 18 a 22 | 0 | a·b·b·a·b | 0,47 |
| Kevin | Contemplativo | tranquilo | 23 a 28 | 0 | b·b·a·b·b | 0,39 |
| Andrés | Contemplativo | tranquilo | 23 a 28 | 1 | b·b·b·a·b | 0,34 |
| Cristian | Contemplativo | tranquilo | 23 a 28 | 2 | b·b·a·a·b | 0,36 |
| Kevin | Parchadito social | rápido | 18 a 22 | 2 | — | 0,90 |

### Parche Samán B · Ciudad de Cali · 9:30 a. m. · Caminar (5 personas)

- Mismo parche: estación Ciudad de Cali, 9:30 a. m., caminar.
- Ritmo: todos van a ritmo moderado.
- Edad: todos entre 18 y 22 años.
- Experiencia: de 0 a 1 domingos con parche.
- Estilo, entre quienes respondieron el quiz: «Paramos todos: nadie se queda» (3 de 3); «Hace rato en la estación» (3 de 3); «Foto del grupo y a la casa» (2 de 3).

| Integrante | Perfil (simulado) | Ritmo | Edad | Domingos | Quiz 1 a 5 | Distancia al centro |
|---|---|---|---|---|---|---|
| Mateo | Madrugador cumplido | moderado | 18 a 22 | 0 | b·c·b·a·a | 0,15 |
| Sara | Madrugador cumplido | moderado | 18 a 22 | 0 | c·c·a·a·a | 0,11 |
| Sebastián | Contemplativo | moderado | 18 a 22 | 0 | — | 0,10 |
| Mariana | Parchadito social | moderado | 18 a 22 | 0 | — | 0,10 |
| Sofía | Contemplativo | moderado | 18 a 22 | 1 | b·b·a·a·a | 0,18 |

### Parche Samán C · Ciudad de Cali · 9:30 a. m. · Caminar (5 personas)

- Mismo parche: estación Ciudad de Cali, 9:30 a. m., caminar.
- Ritmo: 4 de 5 van a ritmo moderado.
- Edad: todos entre 23 y 28 años.
- Experiencia: de 0 a 1 domingos con parche.
- Estilo, entre quienes respondieron el quiz: «Depende de cómo esté el ambiente» (2 de 2); «Un rato de charla, un rato de silencio» (2 de 2); «La de siempre, a la fija» (2 de 2).

| Integrante | Perfil (simulado) | Ritmo | Edad | Domingos | Quiz 1 a 5 | Distancia al centro |
|---|---|---|---|---|---|---|
| Brayan | Parchadito social | moderado | 23 a 28 | 0 | — | 0,16 |
| Julián | Madrugador cumplido | moderado | 23 a 28 | 1 | c·c·a·b·a | 0,17 |
| Esteban | Madrugador cumplido | moderado | 23 a 28 | 1 | c·c·a·a·a | 0,17 |
| Melissa | Parchadito social | moderado | 23 a 28 | 1 | — | 0,12 |
| Brayan | Madrugador cumplido | rápido | 23 a 28 | 1 | — | 0,41 |

### Parche Carbonero A · San Carlos · 8:00 a. m. · Caminar (4 personas)

- Mismo parche: estación San Carlos, 8:00 a. m., caminar.
- Ritmo: todos van a ritmo tranquilo.
- Edad: todos entre 18 y 22 años.
- Experiencia: de 0 a 1 domingos con parche.
- Estilo, entre quienes respondieron el quiz: «¡Jugo y charla con el parche!» (2 de 2); «Echando cuento todo el camino» (2 de 2); «¡Nueva! A ver qué aparece» (2 de 2).

| Integrante | Perfil (simulado) | Ritmo | Edad | Domingos | Quiz 1 a 5 | Distancia al centro |
|---|---|---|---|---|---|---|
| Felipe | Parchadito social | tranquilo | 18 a 22 | 0 | a·a·b·a·b | 0,13 |
| Ángela | Parchadito social | tranquilo | 18 a 22 | 0 | a·a·b·a·b | 0,13 |
| Karen | Parchadito social | tranquilo | 18 a 22 | 1 | — | 0,13 |
| Duván | Madrugador cumplido | tranquilo | 18 a 22 | 1 | — | 0,13 |

### Parche Carbonero B · San Carlos · 8:00 a. m. · Caminar (4 personas)

- Mismo parche: estación San Carlos, 8:00 a. m., caminar.
- Ritmo: 3 de 4 van a ritmo tranquilo.
- Edad: 3 de 4 entre 23 y 28 años.
- Experiencia: de 1 a 3 domingos con parche.
- Estilo, entre quienes respondieron el quiz: «Un rato de charla, un rato de silencio» (2 de 2); «Paramos todos: nadie se queda» (2 de 2); «Llegando justo con la salida» (2 de 2).

| Integrante | Perfil (simulado) | Ritmo | Edad | Domingos | Quiz 1 a 5 | Distancia al centro |
|---|---|---|---|---|---|---|
| Mariana | Madrugador cumplido | tranquilo | 23 a 28 | 2 | — | 0,30 |
| Cristian | Contemplativo | tranquilo | 23 a 28 | 2 | — | 0,30 |
| Tatiana | Parchadito social | tranquilo | 23 a 28 | 3 | a·c·b·a·b | 0,35 |
| Mateo | Madrugador cumplido | rápido | 18 a 22 | 1 | c·c·a·a·b | 0,89 |

### Parche Ceiba A · Brisas de los Álamos · 9:30 a. m. · Bici (6 personas)

- Mismo parche: estación Brisas de los Álamos, 9:30 a. m., bici.
- Ritmo: 4 de 6 van a ritmo tranquilo.
- Edad: 5 de 6 entre 18 y 22 años.
- Experiencia: de 0 a 3 domingos con parche.
- Estilo, entre quienes respondieron el quiz: «¡Nueva! A ver qué aparece» (3 de 4); «Paramos todos: nadie se queda» (3 de 4); «Llegando justo con la salida» (3 de 4).

| Integrante | Perfil (simulado) | Ritmo | Edad | Domingos | Quiz 1 a 5 | Distancia al centro |
|---|---|---|---|---|---|---|
| Vanessa | Contemplativo | tranquilo | 18 a 22 | 0 | — | 0,38 |
| Paula | Parchadito social | tranquilo | 18 a 22 | 0 | c·a·b·a·b | 0,40 |
| Óscar | Parchadito social | tranquilo | 18 a 22 | 1 | c·c·b·a·b | 0,37 |
| Ángela | Contemplativo | tranquilo | 18 a 22 | 1 | a·a·a·a·b | 0,41 |
| Alejandro | Deportista | rápido | 18 a 22 | 3 | b·b·b·b·a | 0,77 |
| Yuliana | Madrugador cumplido | rápido | 23 a 28 | 1 | — | 0,83 |

### Parche Ceiba B · Brisas de los Álamos · 9:30 a. m. · Bici (6 personas)

- Mismo parche: estación Brisas de los Álamos, 9:30 a. m., bici.
- Ritmo: todos van a ritmo moderado.
- Edad: todos entre 18 y 22 años.
- Experiencia: de 0 a 1 domingos con parche.
- Estilo, entre quienes respondieron el quiz: «Foto del grupo y a la casa» (3 de 4); «En mi mundo, gozándome el paisaje» (3 de 4); «La de siempre, a la fija» (3 de 4).

| Integrante | Perfil (simulado) | Ritmo | Edad | Domingos | Quiz 1 a 5 | Distancia al centro |
|---|---|---|---|---|---|---|
| Valentina | Contemplativo | moderado | 18 a 22 | 0 | b·b·a·a·b | 0,17 |
| Yeimi | Madrugador cumplido | moderado | 18 a 22 | 0 | — | 0,12 |
| Melissa | Contemplativo | moderado | 18 a 22 | 1 | b·b·a·a·b | 0,15 |
| Julián | Deportista | moderado | 18 a 22 | 1 | b·b·b·b·a | 0,25 |
| Cristian | Contemplativo | moderado | 18 a 22 | 1 | — | 0,09 |
| Vanessa | Contemplativo | moderado | 18 a 22 | 1 | a·c·a·a·b | 0,19 |

### Parche Ceiba C · Brisas de los Álamos · 9:30 a. m. · Bici (5 personas)

- Mismo parche: estación Brisas de los Álamos, 9:30 a. m., bici.
- Ritmo: 4 de 5 van a ritmo tranquilo.
- Edad: todos entre 23 y 28 años.
- Experiencia: de 0 a 2 domingos con parche.
- Estilo, entre quienes respondieron el quiz: «Paramos todos: nadie se queda» (4 de 4); «Echando cuento todo el camino» (3 de 4); «La de siempre, a la fija» (3 de 4).

| Integrante | Perfil (simulado) | Ritmo | Edad | Domingos | Quiz 1 a 5 | Distancia al centro |
|---|---|---|---|---|---|---|
| Cristian | Contemplativo | tranquilo | 23 a 28 | 0 | b·b·a·a·a | 0,29 |
| Anderson | Parchadito social | tranquilo | 23 a 28 | 1 | — | 0,15 |
| Anderson | Contemplativo | tranquilo | 23 a 28 | 1 | c·a·a·a·b | 0,15 |
| Juan | Parchadito social | tranquilo | 23 a 28 | 2 | a·a·a·a·b | 0,21 |
| Karen | Parchadito social | moderado | 23 a 28 | 1 | a·a·b·a·b | 0,44 |

### Parche Samán A · Torres de Comfandi · 8:00 a. m. · Caminar (5 personas)

- Mismo parche: estación Torres de Comfandi, 8:00 a. m., caminar.
- Ritmo: todos van a ritmo moderado.
- Edad: todos entre 18 y 22 años.
- Experiencia: de 0 a 1 domingos con parche.
- Estilo, entre quienes respondieron el quiz: «La de siempre, a la fija» (4 de 4); «Paramos todos: nadie se queda» (3 de 4); «Llegando justo con la salida» (3 de 4).

| Integrante | Perfil (simulado) | Ritmo | Edad | Domingos | Quiz 1 a 5 | Distancia al centro |
|---|---|---|---|---|---|---|
| David | Contemplativo | moderado | 18 a 22 | 0 | b·b·a·a·b | 0,19 |
| Alejandro | Madrugador cumplido | moderado | 18 a 22 | 0 | — | 0,11 |
| Camila | Madrugador cumplido | moderado | 18 a 22 | 0 | c·a·a·a·b | 0,13 |
| Brayan | Madrugador cumplido | moderado | 18 a 22 | 1 | c·c·a·a·b | 0,12 |
| Yuliana | Madrugador cumplido | moderado | 18 a 22 | 1 | a·a·a·b·a | 0,25 |

### Parche Samán B · Torres de Comfandi · 8:00 a. m. · Caminar (4 personas)

- Mismo parche: estación Torres de Comfandi, 8:00 a. m., caminar.
- Ritmo: 2 de 4 van a ritmo tranquilo.
- Edad: 3 de 4 entre 23 y 28 años.
- Experiencia: de 1 a 2 domingos con parche.
- Estilo, entre quienes respondieron el quiz: «¡Jugo y charla con el parche!» (3 de 4); «La de siempre, a la fija» (3 de 4); «Paramos todos: nadie se queda» (3 de 4).

| Integrante | Perfil (simulado) | Ritmo | Edad | Domingos | Quiz 1 a 5 | Distancia al centro |
|---|---|---|---|---|---|---|
| Andrés | Contemplativo | tranquilo | 23 a 28 | 1 | a·b·a·b·b | 0,47 |
| Sebastián | Parchadito social | tranquilo | 23 a 28 | 2 | a·a·b·a·a | 0,47 |
| Cristian | Parchadito social | moderado | 23 a 28 | 1 | a·a·a·a·b | 0,25 |
| Manuela | Madrugador cumplido | rápido | 18 a 22 | 1 | b·c·a·a·a | 0,80 |

### Parche Samán C · Torres de Comfandi · 8:00 a. m. · Caminar (4 personas)

- Mismo parche: estación Torres de Comfandi, 8:00 a. m., caminar.
- Ritmo: todos van a ritmo moderado.
- Edad: todos entre 23 y 28 años.
- Experiencia: de 0 a 1 domingos con parche.
- Estilo, entre quienes respondieron el quiz: «Paramos todos: nadie se queda» (4 de 4); «Un rato de charla, un rato de silencio» (3 de 4); «La de siempre, a la fija» (3 de 4).

| Integrante | Perfil (simulado) | Ritmo | Edad | Domingos | Quiz 1 a 5 | Distancia al centro |
|---|---|---|---|---|---|---|
| Vanessa | Madrugador cumplido | moderado | 23 a 28 | 0 | b·c·a·a·a | 0,14 |
| Luisa | Contemplativo | moderado | 23 a 28 | 1 | b·b·a·a·b | 0,18 |
| Santiago | Madrugador cumplido | moderado | 23 a 28 | 1 | c·c·a·a·a | 0,10 |
| Andrés | Madrugador cumplido | moderado | 23 a 28 | 1 | c·c·b·a·a | 0,17 |

### Parche Caracolí A · La Luna · 8:00 a. m. · Caminar (5 personas)

- Mismo parche: estación La Luna, 8:00 a. m., caminar.
- Ritmo: todos van a ritmo tranquilo.
- Edad: todos entre 18 y 22 años.
- Experiencia: de 0 a 2 domingos con parche.
- Estilo, entre quienes respondieron el quiz: «¡Nueva! A ver qué aparece» (4 de 5); «Paramos todos: nadie se queda» (4 de 5); «Llegando justo con la salida» (4 de 5).

| Integrante | Perfil (simulado) | Ritmo | Edad | Domingos | Quiz 1 a 5 | Distancia al centro |
|---|---|---|---|---|---|---|
| Yeimi | Contemplativo | tranquilo | 18 a 22 | 0 | b·b·a·b·b | 0,32 |
| Óscar | Parchadito social | tranquilo | 18 a 22 | 0 | a·c·b·a·b | 0,17 |
| Mariana | Contemplativo | tranquilo | 18 a 22 | 1 | b·c·b·a·b | 0,14 |
| Nicolás | Parchadito social | tranquilo | 18 a 22 | 2 | a·a·b·a·b | 0,19 |
| Sofía | Parchadito social | tranquilo | 18 a 22 | 2 | a·a·b·a·a | 0,24 |

### Parche Caracolí B · La Luna · 8:00 a. m. · Caminar (5 personas)

- Mismo parche: estación La Luna, 8:00 a. m., caminar.
- Ritmo: 4 de 5 van a ritmo moderado.
- Edad: todos entre 23 y 28 años.
- Experiencia: de 0 a 2 domingos con parche.
- Estilo, entre quienes respondieron el quiz: «Paramos todos: nadie se queda» (4 de 4); «Un rato de charla, un rato de silencio» (3 de 4); «Llegando justo con la salida» (3 de 4).

| Integrante | Perfil (simulado) | Ritmo | Edad | Domingos | Quiz 1 a 5 | Distancia al centro |
|---|---|---|---|---|---|---|
| Jhon | Contemplativo | tranquilo | 23 a 28 | 1 | b·c·a·a·b | 0,43 |
| Karen | Madrugador cumplido | moderado | 23 a 28 | 0 | c·c·a·a·a | 0,22 |
| Vanessa | Madrugador cumplido | moderado | 23 a 28 | 0 | — | 0,16 |
| Ángela | Madrugador cumplido | moderado | 23 a 28 | 0 | c·c·b·a·b | 0,17 |
| Anderson | Parchadito social | moderado | 23 a 28 | 2 | a·a·b·a·b | 0,27 |

### Parche Caracolí C · La Luna · 8:00 a. m. · Caminar (5 personas)

- Mismo parche: estación La Luna, 8:00 a. m., caminar.
- Ritmo: todos van a ritmo moderado.
- Edad: todos entre 18 y 22 años.
- Experiencia: de 0 a 2 domingos con parche.
- Estilo, entre quienes respondieron el quiz: «Paramos todos: nadie se queda» (4 de 4); «Hace rato en la estación» (4 de 4); «Depende de cómo esté el ambiente» (3 de 4).

| Integrante | Perfil (simulado) | Ritmo | Edad | Domingos | Quiz 1 a 5 | Distancia al centro |
|---|---|---|---|---|---|---|
| Juan | Madrugador cumplido | moderado | 18 a 22 | 0 | — | 0,18 |
| Mateo | Madrugador cumplido | moderado | 18 a 22 | 1 | b·c·b·a·a | 0,17 |
| Miguel | Madrugador cumplido | moderado | 18 a 22 | 1 | c·b·a·a·a | 0,11 |
| Felipe | Madrugador cumplido | moderado | 18 a 22 | 1 | c·c·a·a·a | 0,07 |
| Luisa | Madrugador cumplido | moderado | 18 a 22 | 2 | c·c·a·a·a | 0,15 |

### Parche Caracolí D · La Luna · 8:00 a. m. · Caminar (4 personas)

- Mismo parche: estación La Luna, 8:00 a. m., caminar.
- Ritmo: 3 de 4 van a ritmo rápido.
- Edad: 3 de 4 entre 18 y 22 años.
- Experiencia: de 0 a 1 domingos con parche.
- Estilo, entre quienes respondieron el quiz: «La de siempre, a la fija» (3 de 3); «Paramos todos: nadie se queda» (3 de 3); «Depende de cómo esté el ambiente» (2 de 3).

| Integrante | Perfil (simulado) | Ritmo | Edad | Domingos | Quiz 1 a 5 | Distancia al centro |
|---|---|---|---|---|---|---|
| Valentina | Contemplativo | tranquilo | 23 a 28 | 1 | b·b·a·a·b | 0,89 |
| Brayan | Madrugador cumplido | rápido | 18 a 22 | 0 | c·c·a·a·a | 0,31 |
| Sofía | Madrugador cumplido | rápido | 18 a 22 | 0 | — | 0,32 |
| Gabriela | Madrugador cumplido | rápido | 18 a 22 | 1 | c·c·a·a·a | 0,31 |

