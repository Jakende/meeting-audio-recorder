# meeting-audio-recorder

Robuste CLI-Aufzeichnung von Online-Meetings unter macOS mit `ffmpeg` und BlackHole 2ch.

[![Status](https://img.shields.io/badge/Status-Bereit-grün.svg)](https://github.com/ExistentialAudio/BlackHole)
[![LICENSE](https://img.shields.io/badge/Lizenz-MIT-brightgreen.svg)](LICENSE)

Ein einfaches, aber leistungsfähiges Toolset für die Audioaufzeichnung von Online-Meetings (Zoom, Teams, BBB, etc.) mit hoher Qualität und minimaler Konfiguration.

## Zielbild

Es gibt zwei praxistaugliche Varianten:

- Variante A: Nur Systemaudio aufzeichnen.
- Variante B: Systemaudio und Mikrofon in eine gemeinsame Stereoaufnahme mischen.

Die Skripte in `scripts/` sind auf ein typisches aktuelles macOS-System ausgelegt und validieren die erwarteten Audio-Geräte zur Laufzeit. Die konkrete Benennung der Geräte im Audio-MIDI-Setup ist wichtig, weil `ffmpeg` unter `avfoundation` genau diese Namen bzw. Indizes sieht.

## Annahmen

- `blackhole-2ch` ist bereits installiert.
- `ffmpeg` ist installiert und über `PATH` verfügbar.
- Die Meeting-App ist entweder eine native App oder ein Browser und nutzt die macOS-Standardausgabe.
- Das eingebaute Mikrofon heißt typischerweise `MacBook Pro Microphone`; bei externen Interfaces muss der Name in den Skripten angepasst werden.
- Das BlackHole-Device soll im Audio-MIDI-Setup exakt `BlackHole 2ch` heißen.

## Audio-MIDI-Setup

### Variante A: Nur Systemaudio

Ziel: Systemaudio in BlackHole einspeisen und mit `ffmpeg` direkt von BlackHole aufzeichnen.

1. Öffne `Audio-MIDI-Setup`.
2. Stelle sicher, dass `BlackHole 2ch` vorhanden ist.
3. Optional, aber praxistauglich: Erstelle ein `Multi-Output Device` mit diesem Namen:
   - `Meeting Output`
4. Aktiviere innerhalb von `Meeting Output` diese Ausgänge:
   - `BlackHole 2ch`
   - dein normaler Abhör-Ausgang, z. B. `MacBook Pro Speakers`, `External Headphones` oder ein USB-Headset
5. Setze bei `BlackHole 2ch` im Multi-Output optional `Drift Correction`, nicht jedoch beim Clock-Device.
6. Setze in macOS `Systemeinstellungen -> Ton -> Ausgabe` das Standard-Ausgabegerät auf:
   - `Meeting Output`
7. Lasse in Zoom, Teams, BBB oder Browser-Calls die Ausgabe auf `System Standard` oder explizit `Meeting Output`.

Signalfluss:

`Meeting-App/Systemaudio -> Meeting Output -> (BlackHole 2ch + Lautsprecher/Kopfhörer)`

Aufzeichnung in `ffmpeg`:

- Eingabegerät: `BlackHole 2ch`
- Ergebnis: nur Systemaudio

### Variante B: Systemaudio + Mikrofon in einem gemeinsamen Stream

Ziel: Systemaudio über BlackHole abgreifen, Mikrofon separat einspeisen und beide Signale in `ffmpeg` zu einer gemeinsamen Stereoaufnahme mischen.

Es gibt zwei saubere Wege. Bevorzugt wird hier die `ffmpeg`-Mischung, weil sie reproduzierbarer und leichter skriptbar ist.

#### B1. Empfohlene Praxis: ffmpeg mischt zwei Eingänge

1. Behalte `Meeting Output` aus Variante A bei.
2. Verwende als Standard-Ausgabe weiterhin `Meeting Output`.
3. Wähle in der Meeting-Software als Mikrofon dein echtes Mikrofon:
   - z. B. `MacBook Pro Microphone` oder ein USB-Mikrofon
4. In `ffmpeg` werden zwei Audioquellen geöffnet:
   - `BlackHole 2ch` für Systemaudio
   - `MacBook Pro Microphone` oder ein anderes Mikrofon für Spracheingang
5. `ffmpeg` mischt beide zu einer Stereoaufnahme.

Vorteil:

- Kein zusätzliches Aggregate Device notwendig.
- Die Meeting-App bleibt sauber konfiguriert.
- Aufnahme und Mischung sind transparent und im Skript nachvollziehbar.

#### B2. Alternative: Aggregate Device für ein kombiniertes Eingabegerät

Nur nötig, wenn du in Tools unbedingt ein einziges kombiniertes Eingabegerät sehen willst.

1. Erstelle in `Audio-MIDI-Setup` ein `Aggregate Device` mit diesem Namen:
   - `Meeting Capture Aggregate`
2. Füge hinzu:
   - `BlackHole 2ch`
   - `MacBook Pro Microphone` oder dein externes Mikrofon
3. Setze als Clock Source das stabilere physische Gerät, meist das Mikrofon oder das externe Interface.
4. Aktiviere `Drift Correction` auf dem jeweils anderen Gerät.
5. Die Kanalbelegung ist danach typischerweise:
   - Kanäle 1-2: BlackHole 2ch
   - weitere Kanäle: Mikrofon
6. In `ffmpeg` muss dieses Aggregate Device geöffnet und die passenden Kanäle selektiert/gemischt werden.

Wichtiger Hinweis:

- Aggregate Devices funktionieren, sind aber fehleranfälliger als zwei direkte `ffmpeg`-Inputs.
- Für die eigentliche Aufzeichnung ist B1 in der Regel robuster.

## Geräte in ffmpeg / avfoundation referenzieren

Geräteliste ausgeben:

```bash
ffmpeg -f avfoundation -list_devices true -i ""
```

Die relevanten Audio-Geräte erscheinen z. B. so:

```text
[0] BlackHole 2ch
[1] MacBook Pro Microphone
[2] Meeting Capture Aggregate
```

`ffmpeg` kann Geräte per Index oder Namen öffnen. Namen sind lesbarer, Indizes können sich aber ändern. Die Skripte prüfen Namen und lösen dann den aktuellen Index auf.

## Standardparameter

Empfohlene `ffmpeg`-Parameter:

- Samplerate: `48000`
- Kanäle: `2`
- Codec: `aac`
- Bitrate: `192k`
- Container: `m4a`

Begründung:

- 48 kHz passt zu typischen Video- und Meeting-Audio-Pipelines.
- AAC in M4A ist breit kompatibel und für Sprache plus Systemaudio ausreichend effizient.
- Stereo wird erzwungen, damit gemischte Signale konsistent landen.

## Direkte ffmpeg-Befehle

### Geräte anzeigen

```bash
ffmpeg -f avfoundation -list_devices true -i ""
```

### Variante A: nur Systemaudio über BlackHole 2ch

```bash
OUT="meeting_$(date +%Y%m%d_%H%M).m4a"
ffmpeg -hide_banner -loglevel warning \
  -f avfoundation -thread_queue_size 512 -i ":BlackHole 2ch" \
  -vn \
  -ar 48000 -ac 2 \
  -c:a aac -b:a 192k \
  "$OUT"
```

Hinweis:

- Das `:` vor `BlackHole 2ch` bedeutet bei `avfoundation`: kein Video, nur dieses Audio-Device.

### Variante B: Systemaudio + Mikrofon in ffmpeg mischen

```bash
OUT="meeting_$(date +%Y%m%d_%H%M).m4a"
ffmpeg -hide_banner -loglevel warning \
  -f avfoundation -thread_queue_size 512 -i ":BlackHole 2ch" \
  -f avfoundation -thread_queue_size 512 -i ":MacBook Pro Microphone" \
  -filter_complex "[0:a][1:a]amix=inputs=2:duration=longest:dropout_transition=2,volume=2[a]" \
  -map "[a]" \
  -vn \
  -ar 48000 -ac 2 \
  -c:a aac -b:a 192k \
  "$OUT"
```

Hinweise:

- `amix` summiert beide Quellen.
- `volume=2` kompensiert teilweise die Pegelabsenkung durch `amix`; bei lautem Material ggf. auf `1.5` reduzieren.
- Für sehr empfindliche Mikrofone kann zusätzlich `-filter_complex "[1:a]volume=1.2[mic];[0:a][mic]amix=..."` sinnvoll sein.

## Skripte

### Schnellstart

1. Systemprüfung durchführen:

```bash
./scripts/check.sh
```

Dieser Befehl überprüft alle Abhängigkeiten und die Audio-Geräte-Konfiguration.

2. Geräte anzeigen:

```bash
./scripts/list_audio_devices.sh
```

3. Aufnahme starten (Variante A - nur Systemaudio):

```bash
./scripts/record.sh start-a
```

4. Aufnahme starten (Variante B - Systemaudio + Mikrofon):

```bash
./scripts/record.sh start-b
```

5. Aufnahme starten mit spezifischem Mikrofon:

```bash
MIC_DEVICE="Jakob Endemann Microphone" ./scripts/record.sh start-b
```

6. Aufnahme stoppen:

```bash
./scripts/record.sh stop
```

7. Status anzeigen:

```bash
./scripts/record.sh status
```

8. Aufnahmen verwalten:

```bash
./scripts/manage.sh list          # Alle Aufnahmen auflisten
./scripts/manage.sh clean         # Alte Aufnahmen (30 Tage) löschen
./scripts/manage.sh clean 7       # Aufnahmen älter als 7 Tage löschen
./scripts/manage.sh info DATEI    # Details zu einer Aufnahme anzeigen
./scripts/manage.sh open          # Aufnahmen-Ordner öffnen
```

9. Interaktives Menü:

```bash
./scripts/record.sh
```

oder einfach:

```bash
./scripts/record.sh menu
```

### Umgebungsvariablen

Alle Skripte unterstützen diese Umgebungsvariablen (können auch in `config.env` gespeichert werden):

- `BLACKHOLE_DEVICE` - Name des BlackHole-Geräts (Standard: `BlackHole 2ch`)
- `MIC_DEVICE` - Name des Mikrofon-Geräts (Standard: `MacBook Pro Microphone`)
- `OUTPUT_DIR` - Zielordner für Aufnahmen (Standard: `./recordings`)
- `SAMPLE_RATE` - Abtastrate (Standard: `48000`)
- `BITRATE` - Bitrate (Standard: `192k`)
- `AUDIO_CODEC` - Audio-Codec (Standard: `aac`)
- `CONTAINER_FORMAT` - Container-Format (Standard: `m4a`)

Beispiel für persistente Konfiguration:

```bash
# Bearbeiten Sie config.env
nano config.env

# Oder setzen Sie Umgebungsvariablen temporär
BLACKHOLE_DEVICE="My BlackHole" MIC_DEVICE="External Mic" ./scripts/record.sh start-b
```

### Einrichtungsassistent

Für neue Benutzer gibt es einen Einrichtungsassistenten:

```bash
./scripts/setup.sh
```

Dieser Assistent führt Sie durch:
- Abhängigkeitsprüfung
- BlackHole 2ch Verifizierung
- Mikrofonauswahl
- Konfigurationsdatei Erstellung

## Verfügbare Skripte

| Skript | Beschreibung |
|--------|--------------|
| `scripts/record.sh` | Hauptskript mit interaktivem Menü und allen Funktionen |
| `scripts/check.sh` | Systemprüfung und Validierung |
| `scripts/setup.sh` | Einrichtungsassistent für neue Benutzer |
| `scripts/list_audio_devices.sh` | Liste alle verfügbaren Audio-Geräte |
| `scripts/record_system_audio.sh` | Startet Aufnahme Variante A (nur Systemaudio) |
| `scripts/record_system_plus_mic.sh` | Startet Aufnahme Variante B (Systemaudio + Mikrofon) |
| `scripts/stop.sh` | Stoppt die aktuelle Aufnahme |
| `scripts/manage.sh` | Aufnahmen verwalten (listen, löschen, info) |

## Anpassbare Umgebungsvariablen

Alle Skripte unterstützen diese Variablen (können in `config.env` oder als Umgebungsvariablen gesetzt werden):

- `OUTPUT_DIR` - Zielordner für Aufnahmen, Standard: `recordings`
- `BLACKHOLE_DEVICE` - Standard: `BlackHole 2ch`
- `MIC_DEVICE` - Standard: `MacBook Pro Microphone`
- `SAMPLE_RATE` - Standard: `48000`
- `BITRATE` - Standard: `192k`
- `AUDIO_CODEC` - Standard: `aac` (alternativ: `libmp3lame` für MP3, `libopus` für Opus)
- `CONTAINER_FORMAT` - Standard: `m4a` (alternativ: `mp3`, `wav`, `ogg`)

## Typische Fehlerbilder

### `BlackHole 2ch` wird in `ffmpeg` nicht angezeigt

Prüfen:

- Ist BlackHole wirklich installiert?
- Ist das macOS-Audio-Subsystem nach der Installation einmal neu initialisiert worden?
- Taucht das Gerät in `Audio-MIDI-Setup` auf?
- Zeigt `./scripts/list_audio_devices.sh` es an?

### Kein Ton in der Systemaudio-Aufnahme

Prüfen:

- Ist das Standard-Ausgabegerät wirklich `Meeting Output` oder direkt `BlackHole 2ch`?
- Nutzt die Meeting-App eventuell ein eigenes Ausgabe-Device statt `System Standard`?
- Hört man lokal über den zweiten Ausgang des Multi-Output-Devices noch mit?

### Mikrofon fehlt in Variante B

Prüfen:

- Name mit `./scripts/list_audio_devices.sh` kontrollieren.
- `MIC_DEVICE` explizit setzen.
- macOS-Mikrofonberechtigung für Terminal/iTerm prüfen.

## Empfehlung

Für die Praxis ist diese Kombination am robustesten:

- Systemausgabe: `Meeting Output` (Multi-Output mit `BlackHole 2ch` + Lautsprecher/Kopfhörer)
- Aufnahme A: `BlackHole 2ch`
- Aufnahme B: `BlackHole 2ch` + echtes Mikrofon direkt in `ffmpeg` mischen

Damit bleibt die Konfiguration klar, testbar und ohne unnötig komplexe Aggregate-Device-Abhängigkeiten.

## Erweiterte Funktionen

### PID-Management
Das System verwaltet jetzt automatisch PID-Dateien, sodass Sie:
- Laufende Aufnahmen mit `./scripts/record.sh stop` stoppen können
- Den Status mit `./scripts/record.sh status` prüfen können
- Nicht mehr manuell PIDs suchen müssen

### Logging
Alle wichtigen Aktionen werden in `recording.log` protokolliert:
- Start/Stop von Aufnahmen
- Fehler und Warnungen
- Systemprüfungen

### Konfigurationsdatei
Alle Einstellungen können persistent in `config.env` gespeichert werden. Führen Sie `./scripts/setup.sh` aus, um eine Konfiguration zu erstellen, oder bearbeiten Sie die Datei manuell.

### Aufnahmen-Verwaltung
Mit `./scripts/manage.sh` können Sie:
- Alle Aufnahmen auflisten (`list`)
- Alte Aufnahmen bereinigen (`clean [TAGE]`)
- Informationen zu einer Aufnahme anzeigen (`info DATEI`)
- Den Aufnahmen-Ordner öffnen (`open`)

## Beispiele für erweiterte Nutzung

### MP3-Aufnahmen
```bash
AUDIO_CODEC="libmp3lame" CONTAINER_FORMAT="mp3" ./scripts/record.sh start-a
```

### Höhere Qualität
```bash
BITRATE="320k" SAMPLE_RATE="96000" ./scripts/record.sh start-b
```

### Unterschiedlicher Ausgabeordner
```bash
OUTPUT_DIR="$HOME/Meetings" ./scripts/record.sh start-a
```

### Mit spezifischem Gerät
```bash
BLACKHOLE_DEVICE="BlackHole 16ch" MIC_DEVICE="Rode NT-USB" ./scripts/record.sh start-b
```

### Automatisches Starten mit Cron
```bash
# Fügen Sie dies Ihrer crontab hinzu, um z.B. um 9 Uhr morgens eine Aufnahme zu starten
0 9 * * * cd /path/to/meeting-audio-recorder && ./scripts/record.sh start-a

# Und um 17 Uhr zu stoppen
0 17 * * * cd /path/to/meeting-audio-recorder && ./scripts/record.sh stop
```

## Fehlersuche

### Log-Datei anzeigen
```bash
tail -f recording.log
```

### Detaillierte ffmpeg-Ausgabe
Entfernen Sie `-loglevel warning` aus dem Skript oder setzen Sie:
```bash
FFMPEG_LOGLEVEL="info" ./scripts/record.sh start-a
```

### Prüfen, ob ffmpeg Geräte sieht
```bash
ffmpeg -f avfoundation -list_devices true -i ""
```

### Prüfen, ob BlackHole funktioniert
```bash
# Spielen Sie Testton ab und leiten Sie ihn durch BlackHole
# Öffnen Sie Audio-MIDI-Setup und prüfen Sie die Pegel auf BlackHole 2ch
```

## Lizenz

Dieses Projekt ist Open Source und kann frei verwendet, modifiziert und verteilt werden. Es gibt keine ausdrückliche Lizenz, daher gelten die Standard-BSD-Regeln.
