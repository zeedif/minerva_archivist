# MiNERVA Archivist

[English](README.md)

Cura colecciones de ROMs contra DATs de No-Intro y Redump: elige un dump por juego (1G1R), descarga lo que falta desde [MiNERVA Archive](https://minerva-archive.org), ordena la carpeta para EmulationStation-DE y pone en cuarentena lo que sobra. La selección sigue los clonelists y metadatos de [Retool](https://github.com/unexpectedpanda/retool).

Es un workspace de Dart: `packages/minerva_core` contiene toda la lógica, `apps/cli` es la línea de comandos y `apps/desktop` una interfaz Flutter sobre los mismos perfiles.

## Compilar

```sh
dart pub get
cd apps/cli && dart build cli          # build/cli/.../bundle/bin/minerva.exe
cd apps/desktop && flutter build windows
```

La carpeta `lib/` del bundle lleva libtorrent y debe quedar junto a `bin/`. Desde el código, `dart run apps/cli/bin/minerva.dart` equivale a `minerva`.

## Uso

```sh
minerva sync                                   # metadatos y DATs de Redump/MAME-Redump en .minerva-cache
minerva select -d "Nintendo - Game Boy" --list # qué se querría; no toca nada
minerva run -d "Nintendo - Game Boy" -r D:/Roms/gb           # solo informa
minerva run -d "Nintendo - Game Boy" -r D:/Roms/gb --apply   # lo ejecuta
```

Los DATs de No-Intro no se pueden redistribuir: descárgalos de Dat-o-Matic en `.minerva-cache/nointro/`. Un DAT se nombra por su sistema, así que la fecha del nombre de archivo no importa; antepón la fuente (`redump:Sony - PlayStation`) cuando dos fuentes comparten nombre. También sirve la ruta a un DAT o a una carpeta de DATs.

`run` pasa por estas etapas. Sin `--apply` no se descarga, mueve ni escribe nada.

| Etapa | Qué hace |
|---|---|
| select | Aplica las opciones de abajo y deja un dump por juego. |
| audit | Empareja archivos con la selección por hash. Las entradas de un zip se identifican por el CRC-32 y el tamaño de su directorio, sin descomprimir. |
| `download` | Baja los juegos que faltan del torrent de la plataforma, solo los archivos necesarios, con progreso por archivo. Nada queda ejecutándose ni sembrando después. |
| `organize` | Renombra al nombre del DAT y aplica `--layout`. |
| `playlists` | Escribe un `.m3u` por juego de varios discos. |
| `prune` | Mueve archivos desconocidos y duplicados a `<raíz>/.trash`. Nunca borra. |

`sync` también corre primero como etapa. Omite etapas con `--skip`.

Una carpeta que guarda un juego junto a archivos tuyos (parches, manuales, traducciones) se deja donde está: nada de su interior se mueve ni se poda, y solo se renombra al nombre del juego cuando contiene exactamente uno. `<raíz>/.minerva` es la carpeta de trabajo de la herramienta.

## Opciones

| Opción | Significado |
|---|---|
| `--lang Es,En` | Prioridad de idioma, mejor primero. Un título que no hable ninguno se descarta. `Other` vale por los no listados y `Unknown` por los títulos sin idioma; `Es` cubre `Es-MX`. Por defecto `En`. |
| `--region USA,Europe` | Prioridad de región; restringe igual que `--lang`. Por defecto, todas. |
| `--priority lang,ra,langcount` | Desempates que eligen entre los dumps de un juego, mejor primero: `lang`, `region`, `ra` (logros, primero el verificado por hash), `langcount`. Por defecto `lang,region,ra`. |
| `--langcount most\|fewest` | Sentido del eje `langcount`. Obligatoria si `--priority` lo nombra, rechazada si no. |
| `--wishlist archivo.jsonc` | Array JSON/JSONC de nombres de juego; vale cualquier grafía regional. Las entradas que no coinciden con nada se informan. |
| `--wishlist-mode absolute\|subset` | `absolute`: todo lo nombrado se selecciona y los demás filtros solo eligen su dump. `subset`: un título nombrado aún debe pasarlos. |
| `--achievements any\|approved` | Solo títulos con RetroAchievements; `approved` deja únicamente los dumps sobre los que se creó el set. |
| `--supersets prefer\|ignore` | Si una edición que contiene el juego base ocupa su lugar. |
| `--compilations never\|fill\|prefer\|first` | Cuánto vale un pack frente a los juegos que contiene. |
| `--exclude demos,bios,...` | Tipos de dump que se descartan sin más. `minerva run --help` los lista. |
| `--layout` | `zip`, `zip-in-folder`, `extracted`, `extracted-in-folder`. |
| `--protect carpeta` | Carpetas de primer nivel que nunca se tocan. |
| `--depth n` | Cuántas carpetas bajo la raíz se recorren; sin límite por defecto. Útil cuando la raíz también contiene árboles profundos que no son ROMs. |

## Perfiles

`<cache>/profiles.jsonc` guarda las opciones por plataforma con esos mismos nombres, de modo que una plataforma es una palabra:

```jsonc
{
  "defaults": { "lang": ["Es", "En"], "layout": "extracted", "exclude": ["demos", "bios"] },
  "profiles": {
    "gb":  { "dat": "Nintendo - Game Boy", "root": "D:/Roms/gb", "achievements": "any" },
    "psx": { "dat": ["mame-redump:Sony - PlayStation", "redump:Sony - PlayStation"], "root": "D:/Roms/psx" }
  }
}
```

```sh
minerva profiles            # los lista
minerva run gb psx --apply  # ejecuta algunos
minerva run --all           # vista previa de todos
```

Un perfil pisa `defaults` y la línea de comandos pisa a ambos. Las rutas relativas se resuelven desde el archivo. Mira [examples/profiles.jsonc](examples/profiles.jsonc). La aplicación de escritorio lee el mismo archivo.

## Licencia

GPL-3.0. Los clonelists y metadatos vienen de [retool-clonelists-metadata](https://github.com/unexpectedpanda/retool-clonelists-metadata). Para trabajar en el código, mira [CONTRIBUTING.md](CONTRIBUTING.md).
