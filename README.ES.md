<h1 align="center">MiNERVA Archivist</h1>

<div align="center">

[![Plataforma](https://img.shields.io/badge/plataforma-Windows%20%7C%20Linux%20%7C%20macOS-lightgrey)](#instalación)
[![Licencia: GPL-3.0](https://img.shields.io/badge/licencia-GPL--3.0-blue)](LICENSE)
[![Dart SDK](https://img.shields.io/badge/dart-%E2%89%A53.12-0175C2)](https://dart.dev)

[English](README.md) · **Español**

</div>

<p align="center">
Un bibliotecario de ROMs para la terminal: elige un juego por título (1G1R),
descarga solo lo que te falta y deja la carpeta ordenada — sin que tengas que
estar encima.
</p>

---

## Qué es

Tienes DATs y una carpeta de ROMs. MiNERVA Archivist lee los DATs, decide qué
versión de cada juego quieres realmente, revisa qué hay ya en disco, baja lo que
falta y lo acomoda todo.

Trae su propio motor 1G1R — un port de la lógica de selección de
[Retool](https://github.com/unexpectedpanda/retool) — así que no hay que pasar
por otra herramienta antes. Los clonelists, metadatos, RetroAchievements y datos
MIA se obtienen directamente de
[`retool-clonelists-metadata`](https://github.com/unexpectedpanda/retool-clonelists-metadata)
y se cachean en local.

## Qué hace

- **Lee cualquier DAT.** Detecta si es No-Intro, Redump o MAME-Redump CHD a
  partir del propio archivo, sin banderas de tipo.
- **Elige un juego por título.** Estado de producción → idioma → región → logros →
  prioridad del clonelist → revisión. Una reedición mejorada sustituye a la edición
  que reemplaza; un pack multijuego cede ante los juegos que lleva salvo que le
  digas lo contrario.
- **Descarta lo que no quieres.** Una sola lista `--exclude` cubre prototipos,
  betas, discos de prueba, discos extra, piratas, volcados MIA, aplicaciones,
  BIOS, manuales, coverdiscs y vídeo, reconocidos por categoría o por nombre.
- **Conserva lo que sí.** Nombrar un idioma o una región te da ese conjunto; la
  lista de deseos y el filtro de logros nombran el suyo, y dicen si se suman o se
  acotan entre ellos.
- **Descarga solo los huecos.** Cruza los juegos que faltan contra el torrent de
  la plataforma y le pasa a `aria2c` únicamente esos archivos.
- **Ordena al terminar.** Cuatro disposiciones compatibles con ES-DE, listas
  `.m3u` para juegos multidisco, y limpieza de huérfanos que mueve a `.trash` en
  vez de borrar.

Todo lo que toca tus archivos es **simulacro por defecto** — añade `--apply`
cuando el plan te convenza.

## Instalación

Dart SDK ≥ 3.12.

```sh
dart pub get

# ejecutar desde el código
dart run bin/minerva_archivist.dart <comando> [opciones]

# o compilar un binario independiente (arranca más rápido)
dart compile exe bin/minerva_archivist.dart -o minerva_archivist
```

Para descargar necesitas [`aria2c`](https://github.com/aria2/aria2/releases) en
el `PATH` o indicado con `--aria2 <ruta>`. Lo demás funciona sin conexión una vez
sincronizado.

## Primeros pasos

```sh
# 1. espeja los metadatos en local (repetible; solo baja lo que cambió)
minerva_archivist sync

# 2. mira cómo queda la selección — no escribe nada
minerva_archivist filter -d <dat-o-carpeta>

# 3. previsualiza el pipeline completo contra tu biblioteca
minerva_archivist run -d <dat-o-carpeta> -r <raiz-roms>

# 4. hazlo de verdad
minerva_archivist run -d <dat-o-carpeta> -r <raiz-roms> --apply
```

Una invocación típica del día a día — español primero, inglés como respaldo, sin
demos ni BIOS, bajando lo que falte:

```sh
minerva_archivist run -d <dat-o-carpeta> -r <raiz-roms> \
  --lang Es,En,Ja \
  --exclude mia,preproduction,demos,pirate,bonus-discs,applications,bios,manuals,video \
  --with-download --extract --apply
```

Cada etapa informa qué descartó y por qué:

```
[select] 404 in DAT -> 309 wanted  (status -89, language -6)
[audit] 0/309 on disk, 309 missing, 0 unknown
[download] 309 missing -> 303 in torrent, 6 not distributed, 102.5 MB
```

## Comandos

| Comando | Qué hace |
|---|---|
| `sync` | Espeja clonelists / metadatos / RetroAchievements / MIA en local |
| `filter` | Muestra la selección 1G1R — sin conexión, solo lectura |
| `audit` | Compara la selección con lo que hay en disco |
| `download` | Baja los juegos que faltan desde el torrent de la plataforma |
| `organize` | Acomoda los archivos en una de las cuatro disposiciones ES-DE |
| `m3u` | Escribe listas para juegos multidisco |
| `prune` | Manda a `.trash` todo lo que no esté seleccionado |
| `run` | Todo lo anterior, en orden |

Cada bandera, cada combinación y el formato de la lista de deseos están en
**[GUIDE.ES.md](GUIDE.ES.md)** ([English](GUIDE.md)).

## Contribuir

La arquitectura, las convenciones de organización y cómo correr las pruebas
están en **[CONTRIBUTING.md](CONTRIBUTING.md)** (en inglés).

## Créditos y licencia

El motor de selección sigue a [Retool](https://github.com/unexpectedpanda/retool)
de unexpectedpanda, y consume sus
[clonelists y metadatos](https://github.com/unexpectedpanda/retool-clonelists-metadata).
Los DATs vienen de los proyectos de preservación
[No-Intro](https://no-intro.org) y [Redump](http://redump.org). Gracias a todos
ellos.

Distribuido bajo la **GNU General Public License v3.0** — ver [LICENSE](LICENSE).

    MiNERVA Archivist  Copyright (C) 2026  Zeedif
    Este programa se distribuye SIN NINGUNA GARANTÍA.
    Es software libre, y puedes redistribuirlo bajo ciertas condiciones.
