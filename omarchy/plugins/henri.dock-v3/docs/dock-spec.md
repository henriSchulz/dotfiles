# Spezifikation: Dock-Komponente im Stil des macOS-Docks

> **Zweck dieses Dokuments:** Ein Coding-Agent soll anhand dieser Spezifikation eine Dock-Komponente bauen, die sich in Aufbau, Verhalten, Animationen und Bedienung wie das macOS-Dock (Stand macOS Sonoma/Sequoia) anfühlt.
>
> **Wichtig für den Agenten:**
> - Alle Zahlenwerte sind **Richtwerte**, die sich am Original orientieren. Sie sind als CSS-Variablen/Konstanten zentral konfigurierbar zu machen, damit sie per Augenmaß feinjustiert werden können.
> - Es dürfen **keine Apple-Assets** verwendet werden (keine Original-App-Icons, keine Apple-Logos, keine SF-Pro-Schriftdateien, keine Markennamen wie „Finder“ im UI). Verwende eigene oder frei lizenzierte Icons und Platzhalternamen.
> - Wo „MUSS“ steht, ist das Verhalten Pflicht; „SOLL“ ist empfohlen; „KANN“ ist optional.

---

## Inhaltsverzeichnis

1. Zielplattform und Tech-Stack
2. Begriffe
3. Aufbau und Layout
4. Visuelles Styling
5. Magnification (Vergrößerungseffekt)
6. Hover-Label (Tooltip)
7. Klick, Start und Bounce-Animationen
8. Laufindikator und Badges
9. Drag & Drop
10. Kontextmenü
11. Stapel (Ordner-Stacks)
12. Minimieren (Genie- und Skalierungseffekt)
13. Automatisches Ein- und Ausblenden
14. Größenänderung über den Trenner
15. Position (unten, links, rechts)
16. Papierkorb
17. Tastatursteuerung
18. Barrierefreiheit und „Bewegung reduzieren“
19. Einstellungen (Konfigurationsobjekt)
20. Datenmodell und Zustände
21. Events / öffentliche API
22. Performance-Anforderungen
23. Abnahmekriterien (Checkliste)

---

## 1. Zielplattform und Tech-Stack

- **Standard-Annahme:** Web-Implementierung mit React + TypeScript, Styling über CSS-Variablen, Animationen über eine Spring-Physik-Bibliothek (z. B. Framer Motion / Motion) oder eigene `requestAnimationFrame`-Schleife.
- Die Komponente wird in einer simulierten „Desktop“-Fläche (Vollbild-Container mit Hintergrundbild) gerendert, damit die Transluzenz sichtbar ist.
- Alle Animationen MÜSSEN auf `transform` und `opacity` basieren (keine Layout-Animationen über `width`/`height`/`top`, außer wo explizit genannt), um 60–120 fps zu erreichen.

## 2. Begriffe

| Begriff | Bedeutung |
|---|---|
| **Dock** | Die gesamte Leiste inkl. Hintergrund. |
| **Kachel (Tile)** | Ein Eintrag im Dock (App, Ordner, minimiertes Fenster, Papierkorb). |
| **Basisgröße** | Kantenlänge einer Kachel ohne Vergrößerung (`tileSize`). |
| **Maximalgröße** | Kantenlänge der Kachel direkt unter dem Cursor bei aktiver Vergrößerung (`magnifiedSize`). |
| **Trenner (Separator)** | Senkrechte (bzw. waagerechte) dünne Linie zwischen Bereichen. |
| **Hauptachse** | Richtung, in der die Kacheln aufgereiht sind (horizontal bei Position unten). |
| **Querachse** | Senkrecht zur Hauptachse (Richtung, in die Icons wachsen und springen). |

## 3. Aufbau und Layout

### 3.1 Bereiche (Reihenfolge entlang der Hauptachse)

1. **App-Bereich**
   - Erste Kachel ist immer der **Dateimanager** (fest, nicht entfernbar, nicht verschiebbar an eine andere Position als Platz 1).
   - Danach angeheftete Apps (vom Nutzer sortierbar).
   - Danach laufende, nicht angeheftete Apps (erscheinen beim Start rechts angehängt, verschwinden beim Beenden).
2. **Trenner**
3. **Zuletzt verwendete Apps** (KANN, abschaltbar, max. 3 Einträge) – gefolgt von einem weiteren **Trenner**.
4. **Dokumentbereich**
   - Ordner-Stapel (z. B. „Downloads“).
   - Minimierte Fenster (als Fenster-Miniatur mit kleinem App-Icon unten rechts), sofern die Option „Fenster in App-Symbol minimieren“ aus ist.
   - Als letzte Kachel immer der **Papierkorb** (fest, nicht entfernbar).

### 3.2 Positionierung

- Standard: am unteren Bildschirmrand, **horizontal zentriert**.
- Abstand der Dock-Unterkante zur Bildschirmkante: ca. **4 px** (Dock „schwebt“ minimal).
- Das Dock ist nur so breit wie sein Inhalt (nie volle Bildschirmbreite).
- Wenn die Kacheln bei Basisgröße nicht passen, MUSS die Basisgröße automatisch verkleinert werden, bis alles passt (Minimum 16 px).

### 3.3 Maße (Richtwerte bei `tileSize = 48`)

| Eigenschaft | Wert |
|---|---|
| Einstellbarer Bereich Basisgröße | 16–128 px |
| Standard-Basisgröße | 48 px |
| Einstellbarer Bereich Maximalgröße | Basisgröße … 128 px |
| Standard-Maximalgröße | 96 px |
| Abstand zwischen Kacheln | ca. 4 % der Basisgröße, mindestens 2 px |
| Innenabstand Dock (Querachse) | ca. 6 px oben und unten |
| Innenabstand Dock (Hauptachse) | ca. 6 px links und rechts |
| Trennerbereich | 1 px Linie + ca. 8 px Abstand je Seite |
| Trennerhöhe | ca. 70 % der Basisgröße, vertikal zentriert |
| Eckenradius Dock-Hintergrund | ca. 18 px bei Basisgröße 48 (skaliert mit ~0,37 × Basisgröße, min. 10 px, max. 26 px) |

### 3.4 Icons

- Icons sind quadratisch mit transparentem Rand; der sichtbare Icon-Körper nimmt ca. **82 %** der Kachel ein (die „Squircle“-Form mit Superellipse-Ecken ist Teil der Icon-Grafik, nicht der Kachel).
- Icons MÜSSEN in mindestens 2× Auflösung der Maximalgröße vorliegen (also 256 px), damit sie beim Vergrößern scharf bleiben.
- Jedes Icon hat einen weichen Schlagschatten innerhalb der Grafik; zusätzlich SOLL die Kachel einen dezenten `drop-shadow(0 1px 1px rgba(0,0,0,0.15))` bekommen.

## 4. Visuelles Styling

### 4.1 Dock-Hintergrund

Der Hintergrund ist eine transluzente, unscharfe „Glas“-Fläche.

```css
:root {
  --dock-radius: 18px;
  --dock-blur: 24px;
  --dock-saturate: 180%;
}

.dock-bg {
  border-radius: var(--dock-radius);
  backdrop-filter: blur(var(--dock-blur)) saturate(var(--dock-saturate));
  -webkit-backdrop-filter: blur(var(--dock-blur)) saturate(var(--dock-saturate));
}

/* Hell */
.theme-light .dock-bg {
  background: rgba(255, 255, 255, 0.28);
  border: 0.5px solid rgba(255, 255, 255, 0.45);
  box-shadow:
    0 0 0 0.5px rgba(0, 0, 0, 0.12),       /* äußere Haarlinie */
    0 10px 30px rgba(0, 0, 0, 0.18);        /* weicher Schatten */
}

/* Dunkel */
.theme-dark .dock-bg {
  background: rgba(30, 30, 30, 0.35);
  border: 0.5px solid rgba(255, 255, 255, 0.18);
  box-shadow:
    0 0 0 0.5px rgba(0, 0, 0, 0.5),
    0 10px 30px rgba(0, 0, 0, 0.35);
}
```

- Der Hintergrund MUSS als eigenes Element hinter den Kacheln liegen und seine Breite (bzw. Höhe bei seitlicher Position) während der Vergrößerung animiert an die Gesamtbreite der Kacheln anpassen.
- Die Höhe des Hintergrunds bleibt bei Vergrößerung **konstant** (Basisgröße + Innenabstand). Vergrößerte Icons ragen **über den Hintergrund hinaus** nach oben.
- Hell/Dunkel folgt `prefers-color-scheme`, überschreibbar per Einstellung.

### 4.2 Trenner

- 1 px breit, Farbe hell: `rgba(0,0,0,0.18)`, dunkel: `rgba(255,255,255,0.22)`.
- Cursor über dem Trenner: `ns-resize` (bei Position unten) bzw. `ew-resize` (seitlich).

### 4.3 Typografie (Label, Menüs)

- Systemschrift-Stack: `-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif` (keine Schriftdateien einbinden).
- Label: 13 px, Gewicht 400; Kontextmenü: 13 px, Gewicht 400.

## 5. Magnification (Vergrößerungseffekt)

### 5.1 Verhalten

- Aktiv nur, wenn `magnification = true`.
- Sobald der Cursor das Dock betritt, wachsen die Kacheln abhängig von ihrem Abstand zum Cursor entlang der Hauptachse.
- Die Kachel direkt unter dem Cursor erreicht `magnifiedSize`, Nachbarn werden stufenlos kleiner, Kacheln außerhalb des Einflussradius bleiben bei Basisgröße.
- Icons wachsen **von der Dock-Grundlinie weg** (bei Position unten nach oben; die Unterkante bleibt fix).
- Durch das Wachsen wird das Dock breiter; die Mitte des Docks bleibt zentriert. Das führt dazu, dass Kacheln unter dem Cursor „durchgleiten“ – genau das ist gewünscht.
- Trenner vergrößern sich nicht, verschieben sich aber mit.

### 5.2 Formel

Für jede Kachel `i` mit Mittelpunkt `c_i` (gemessen im **nicht vergrößerten** Layout) und Cursorposition `x` entlang der Hauptachse:

```
d        = |x - c_i|
R        = tileSize * 3          // Einflussradius (Richtwert: ~3 Kacheln je Seite)
if d >= R: scale_i = 1
else:
  t      = d / R                  // 0 … 1
  falloff = (cos(PI * t) + 1) / 2 // Kosinus-Glocke, 1 in der Mitte, 0 am Rand
  size_i = tileSize + (magnifiedSize - tileSize) * falloff
```

- Die Berechnung MUSS gegen das **Basis-Layout** laufen (nicht gegen die bereits vergrößerten Positionen), sonst entsteht Flattern/Rückkopplung.
- Die resultierenden Größen werden über eine Feder geglättet:
  - Spring: `stiffness 400`, `damping 30`, `mass 0.4` (Richtwert – sehr direkt, kaum Nachschwingen).
- **Eintreten:** Größen federn von Basisgröße zur Zielgröße.
- **Verlassen:** Alle Kacheln federn zurück zur Basisgröße (gleiche Feder).
- Beim Ziehen (Drag) ist die Vergrößerung weiterhin aktiv.
- Modifikator: Hält der Nutzer **Ctrl + Shift** gedrückt, wird die Vergrößerung temporär umgekehrt (ein-/ausgeschaltet) – KANN.

## 6. Hover-Label (Tooltip)

- Erscheint beim Hovern über einer Kachel mit dem Namen der App/des Ordners.
- Position: zentriert über der Kachel, Abstand ca. **10 px** über der Oberkante des **aktuell vergrößerten** Icons (folgt also der Vergrößerung).
- Aussehen:
  - Abgerundetes Rechteck, Radius ~6 px, Innenabstand 4 px × 10 px.
  - Hell: Hintergrund `rgba(240,240,240,0.85)` mit Blur, Text `#1d1d1f`.
  - Dunkel: Hintergrund `rgba(40,40,40,0.85)` mit Blur, Text `#f5f5f7`.
  - Dünne Haarlinie wie beim Dock, leichter Schatten.
  - Kleine Spitze (Dreieck, ca. 10 × 5 px) mittig an der Unterseite, zeigt zur Kachel.
- Erscheinen: sofort (keine Verzögerung), kurzes Einblenden 80 ms.
- Wechsel zwischen Kacheln: Label springt ohne Ausblenden direkt zur neuen Kachel und aktualisiert den Text.
- Ausblenden beim Verlassen des Docks: 100 ms Fade.
- Wird ausgeblendet, sobald ein Kontextmenü oder ein Stapel offen ist.

## 7. Klick, Start und Bounce-Animationen

### 7.1 Gedrückt-Zustand

- Während die Maustaste auf einer Kachel gedrückt ist: Icon wird abgedunkelt (`filter: brightness(0.65)`), ohne Übergangsanimation. Beim Loslassen sofort zurück.

### 7.2 Klick-Verhalten

- App läuft nicht → App „starten“: Start-Bounce (7.3), danach Laufindikator anzeigen, Event `onLaunch`.
- App läuft → App in den Vordergrund holen (`onActivate`). Kein Bounce.
- App läuft und ist aktiv → KANN (Einstellung) alle Fenster der App anzeigen; Standard: nichts tun.
- Ordner → Stapel öffnen (Abschnitt 11).
- Minimiertes Fenster → Fenster wiederherstellen (umgekehrte Minimieren-Animation).

### 7.3 Start-Bounce

- Das Icon hüpft entlang der Querachse (bei Position unten nach oben) wiederholt, solange die App „lädt“.
- Pro Sprung:
  - Höhe: ca. **50 %** der Basisgröße.
  - Aufwärts: 300 ms, Ease-out (`cubic-bezier(0.25, 0.46, 0.45, 0.94)`).
  - Abwärts: 300 ms, Ease-in (`cubic-bezier(0.55, 0.085, 0.68, 0.53)`) – wirkt wie Schwerkraft.
  - Kein Squash/Stretch.
- Für die Demo: Ladezeit simulieren (z. B. 1–3 Bounces, konfigurierbar). Ein laufender Bounce-Zyklus wird immer zu Ende gespielt, bevor gestoppt wird.
- Einstellung `animateOpeningApps = false` deaktiviert den Start-Bounce.
- Der Bounce darf das Layout der Nachbarkacheln nicht verschieben (nur `transform`).

### 7.4 Aufmerksamkeits-Bounce

- Eine laufende App kann Aufmerksamkeit anfordern (`requestAttention(appId)`).
- Sprünge sind **höher** als beim Start (ca. **100 %** der Basisgröße) mit gleicher Kurve, je Sprung ca. 700 ms gesamt, danach 300 ms Pause.
- Wiederholt sich (Standard: 10 Zyklen oder bis die App aktiviert wird).
- Wird durch Klick auf die Kachel sofort beendet (aktueller Sprung darf zu Ende fallen).

## 8. Laufindikator und Badges

### 8.1 Laufindikator

- Kleiner runder Punkt unter jeder laufenden App.
- Durchmesser: 4 px (bei Basisgröße 48; skaliert leicht mit, min. 3 px, max. 5 px).
- Position: mittig unterhalb der Kachel, ca. 2 px über der Innenkante des Dock-Hintergrunds.
- Farbe: hell `rgba(0,0,0,0.75)`, dunkel `rgba(255,255,255,0.8)`.
- Der Punkt bleibt beim Vergrößern **an der Grundlinie** und wächst nicht.
- Erscheinen/Verschwinden: 150 ms Fade.
- Einstellung `showIndicators = false` blendet alle Punkte aus.

### 8.2 Badges

- Rote Plakette oben rechts am Icon, zeigt Zahl oder kurzen Text (z. B. „3“, „99+“, „!“).
- Aussehen: Hintergrund `#ff3b30`, Text weiß, 12 px, Gewicht 500; Höhe ca. 40 % der Kachel (min. 16 px); Breite passt sich dem Inhalt an (Pille), min. = Höhe (Kreis).
- Leichter Schatten `0 1px 2px rgba(0,0,0,0.25)`.
- Skaliert **mit** dem Icon bei Vergrößerung (ist Teil der Kachel-Transformation).
- Erscheinen: Scale-Animation 0 → 1 mit leichter Feder (kurzer Überschwinger).

## 9. Drag & Drop

### 9.1 Umsortieren

- Ziehen startet, wenn die Maus nach dem Drücken mindestens **4 px** bewegt wird (sonst Klick).
- Das gezogene Icon folgt dem Cursor (halbtransparent ist NICHT gewünscht – volle Deckkraft).
- An der Stelle, über der sich das Icon im Dock befindet, öffnet sich eine **Lücke**: die Nachbarkacheln gleiten mit einer Feder (`stiffness 300`, `damping 28`) auseinander.
- Loslassen im Dock: Icon gleitet in die Lücke (200 ms Feder), neue Reihenfolge wird gespeichert (`onReorder`).
- Apps können nur im App-Bereich, Ordner/Dateien nur im Dokumentbereich abgelegt werden. Dateimanager und Papierkorb sind nicht verschiebbar.

### 9.2 Entfernen

- Wird ein Icon so weit aus dem Dock gezogen, dass der Cursor mehr als ca. **1,5 × Basisgröße** vom Dock-Hintergrund entfernt ist (und die Maustaste ca. 400 ms dort gehalten wurde), erscheint über dem Icon das Label **„Entfernen“**, die Lücke im Dock schließt sich.
- Loslassen in diesem Zustand: Icon verschwindet mit kurzer Scale-/Fade-Animation (0,2 s, auf 0,6 × und Deckkraft 0); `onRemove`.
- Laufende Apps werden dabei nur losgelöst (nicht mehr angeheftet), bleiben aber bis zum Beenden im Dock.
- Zurückziehen ins Dock hebt den Entfernen-Zustand auf, die Lücke öffnet sich wieder.

### 9.3 Externe Objekte ablegen

- Datei auf eine App ziehen: App-Kachel wird beim Überfahren hervorgehoben (Icon abgedunkelt wie Gedrückt-Zustand) → Loslassen = `onOpenWith(appId, files)`.
- Datei auf Ordner-Stapel: Kachel hervorheben → `onMoveToFolder`.
- Datei auf Papierkorb: Papierkorb hervorheben → `onTrash`, Papierkorb wechselt auf „voll“.
- Datei in Lücke im Dokumentbereich: fügt Verknüpfung hinzu.
- Während ein externes Objekt über den App-Bereich gezogen wird, öffnen sich **keine** Lücken (außer es ist selbst eine App).

## 10. Kontextmenü

### 10.1 Öffnen

- Rechtsklick, Ctrl+Klick oder **langes Drücken** (ca. 500 ms ohne Bewegung) auf eine Kachel.
- Erscheint über der Kachel, horizontal zentriert, Spitze zeigt auf die Kachel (wie Label).
- Die Vergrößerung friert im aktuellen Zustand ein, solange das Menü offen ist.
- Schließt bei Klick außerhalb, Escape oder Auswahl eines Eintrags.

### 10.2 Aussehen

- Material wie Label, aber größer: Radius ~8 px, Innenabstand 5 px, Mindestbreite 180 px.
- Einträge 22 px hoch, Hover-Hervorhebung: Akzentfarbe (Standard `#0a84ff`) mit weißem Text, Radius 4 px.
- Trennlinien zwischen Gruppen: 1 px, 5 px vertikaler Abstand.
- Untermenüs öffnen sich seitlich mit Pfeil `›` am rechten Rand.

### 10.3 Einträge (App)

1. Liste offener Fenster der App (Häkchen beim aktiven), falls vorhanden
2. — Trenner —
3. **Optionen ›**
   - Im Dock behalten (Häkchen-Toggle)
   - Bei der Anmeldung öffnen (Toggle)
   - Im Dateimanager zeigen
4. — Trenner —
5. Alle Fenster anzeigen
6. Ausblenden
7. **Beenden** – bei gedrückter Wahltaste/Alt ändert sich der Text live zu **„Sofort beenden“**

Bei nicht laufender App: nur „Optionen ›“ und „Öffnen“.

### 10.4 Einträge (Ordner)

- Sortieren nach › (Name, Hinzugefügt, Geändert, Erstellt, Art)
- Anzeigen als › (Ordner, Stapel)
- Inhalt anzeigen als › (Fächer, Raster, Liste, Automatisch)
- Aus dem Dock entfernen
- Im Dateimanager öffnen

### 10.5 Einträge (Trenner)

- Vergrößerung ein/aus
- Position: Links, Unten, Rechts
- Minimieren mit: Trichtereffekt, Linear skalieren
- Automatisch ein- und ausblenden
- Dock-Einstellungen …

### 10.6 Einträge (Papierkorb)

- Öffnen
- Papierkorb entleeren (deaktiviert, wenn leer)

## 11. Stapel (Ordner-Stacks)

Klick auf einen Ordner öffnet dessen Inhalt über dem Dock. Drei Darstellungen:

### 11.1 Fächer

- Bis zu ca. 10–15 Einträge, darüber ein Eintrag „Weitere im Dateimanager“.
- Einträge stehen in einem **leichten Bogen** nach rechts gekrümmt übereinander (unterster Eintrag direkt über der Kachel, Bogen dreht sich bis ca. 15° nach oben hin).
- Jeder Eintrag: Icon (ca. 48 px) + Name links daneben in einer halbtransparenten Pille.
- Animation: Einträge fliegen nacheinander aus der Kachel (Stagger 15 ms), jeweils Translate + Rotation + Fade in 250 ms, Ease-out.

### 11.2 Raster

- Glas-Panel (Material wie Dock), abgerundet, mit Spitze zur Kachel.
- Raster aus Icons (64 px) mit Namen darunter (11 px, max. 2 Zeilen, Ellipse), scrollbar bei vielen Einträgen.
- Animation: Panel skaliert aus der Kachelposition von 0,3 auf 1 mit Fade (250 ms, Feder).

### 11.3 Liste

- Menü-ähnliche Liste mit kleinem Icon (16 px) und Namen, Unterordner öffnen seitlich als Untermenü.

### 11.4 Kachel-Darstellung

- „Stapel“: Kachel zeigt die Icons der obersten 3 Dateien leicht versetzt übereinander.
- „Ordner“: Kachel zeigt ein Ordner-Icon.

## 12. Minimieren (Genie- und Skalierungseffekt)

Für die Demo gibt es simulierte Fenster (einfache Divs mit Titelleiste und gelbem Minimieren-Knopf).

### 12.1 Ziel

- Standard: Fenster wird in eine neue Kachel im Dokumentbereich (links vom Papierkorb) minimiert. Neue Kachel öffnet sich per Lücke (wie beim Drag).
- Option „In App-Symbol minimieren“: Ziel ist die App-Kachel; keine neue Kachel.

### 12.2 Trichtereffekt (Genie)

- Dauer: **500 ms**.
- Das Fenster verformt sich wie ein Trichter: Die Unterkante zieht sich zuerst zur Zielkachel zusammen, dann „fließt“ der Rest des Fensters hinterher, während die Breite zum Ziel hin schmaler wird.
- Umsetzungsvorschlag (Web):
  - Fenster per `html2canvas` o. Ä. in ein Bild rendern (oder das Fenster selbst ist bereits Canvas/SVG-basiert).
  - Bild in N horizontale Streifen (z. B. 40–60) schneiden, jeden Streifen mit eigener Breite, X-Verschiebung und Y-Position animieren.
  - Phase 1 (0–40 %): Seitenkanten verlaufen als S-Kurve (z. B. per Smoothstep) von den Fensterkanten zu den Kachelkanten; die Kurve bildet sich von unten nach oben aus.
  - Phase 2 (40–100 %): Alle Streifen gleiten entlang dieser Kurve nach unten in die Kachel und werden dabei gestaucht.
  - Alternativ WebGL-Mesh mit Vertex-Verschiebung (bessere Qualität).
- Wiederherstellen: exakt umgekehrte Animation.

### 12.3 Lineares Skalieren

- Fenster skaliert gleichmäßig (Transform-Origin berücksichtigt) auf die Kachelgröße und verschiebt sich zur Kachelposition; 300 ms, Ease-in-out; Deckkraft bleibt 1, Miniatur ersetzt am Ende das Fenster.

### 12.4 Zeitlupe

- Minimieren mit gedrückter **Shift**-Taste: Animation ca. **10× langsamer** (KANN, Easter Egg).

## 13. Automatisches Ein- und Ausblenden

- Einstellung `autoHide`.
- Ausgeblendet: Dock ist vollständig aus dem Bildschirm geschoben (Translate entlang der Querachse um Dockhöhe + Abstand).
- **Einblenden:** Cursor berührt die Bildschirmkante (Trigger-Zone 2–4 px hoch, nur über der Breite des Docks) → nach Verzögerung **200 ms** (konfigurierbar, `autoHideDelay`) gleitet das Dock herein.
- **Ausblenden:** Cursor verlässt das Dock (inkl. Label/Menü/Stapel-Bereich) → nach ca. 300 ms gleitet es hinaus.
- Animationsdauer: ca. **350 ms**, Ease-out beim Einblenden, Ease-in beim Ausblenden (`autoHideDuration` konfigurierbar).
- Ist ein Kontextmenü oder Stapel offen, bleibt das Dock sichtbar.
- Beim Aufmerksamkeits-Bounce einer App blendet sich das Dock kurz so weit ein, dass das hüpfende Icon sichtbar ist (KANN).
- Tastenkürzel **Wahl/Alt + Cmd/Ctrl + D** schaltet `autoHide` um.

## 14. Größenänderung über den Trenner

- Maus auf Trenner drücken und entlang der Querachse ziehen → Basisgröße ändert sich **live** (nach oben ziehen = größer).
- Werte werden auf ganze Pixel gerundet, begrenzt auf 16–128 und auf „passt auf den Bildschirm“.
- Mit gedrückter **Wahl/Alt**-Taste rastet die Größe in Stufen ein (16, 32, 48, 64, 128) – KANN.
- Mit gedrückter **Shift**-Taste Trenner zu einer anderen Bildschirmkante ziehen → Position ändert sich (KANN).
- Während des Ziehens ist die Vergrößerung deaktiviert.

## 15. Position (unten, links, rechts)

- `position: "bottom" | "left" | "right"`.
- Links/rechts: Hauptachse vertikal, Dock vertikal zentriert; Icons wachsen und springen nach innen (zur Bildschirmmitte); Label erscheint seitlich neben dem Icon (Spitze zeigt zur Kachel); Laufindikator liegt zwischen Icon und Bildschirmkante.
- Positionswechsel animiert: Dock gleitet an der alten Kante hinaus (250 ms) und an der neuen herein (250 ms).
- Alle Richtungslogiken (Vergrößerung, Bounce, Drag, Menüs, Auto-Hide) MÜSSEN über eine gemeinsame Achsen-Abstraktion laufen, nicht dreifach implementiert werden.

## 16. Papierkorb

- Zwei Icon-Zustände: leer und voll.
- Beim Ziehen eines Laufwerk-Objekts (simuliert) wechselt das Icon zu einem **Auswerfen**-Symbol, das Label zu „Auswerfen“.
- „Papierkorb entleeren“ spielt einen kurzen Sound (KANN, abschaltbar) und wechselt auf „leer“.

## 17. Tastatursteuerung

| Taste | Aktion |
|---|---|
| Ctrl + F3 (bzw. frei definierbares Kürzel) | Fokus ins Dock (erste Kachel) |
| ← / → (↑ / ↓ bei seitlicher Position) | Fokus zur Nachbarkachel; Vergrößerung folgt dem Fokus wie einem Cursor |
| Enter / Leertaste | Kachel aktivieren (wie Klick) |
| ↑ (bei Position unten) | Kontextmenü der fokussierten Kachel öffnen |
| Escape | Menü/Stapel schließen bzw. Fokus verlassen |
| Wahl/Alt + Cmd/Ctrl + D | Auto-Hide umschalten |

- Fokus-Ring: 3 px Akzentfarbe mit Radius passend zum Icon, nur bei Tastaturbedienung (`:focus-visible`).

## 18. Barrierefreiheit und „Bewegung reduzieren“

- Dock ist eine `role="toolbar"` mit `aria-label="Dock"`, `aria-orientation` je nach Position.
- Jede Kachel ist ein `button` mit `aria-label` (Name + Status, z. B. „Notizen, läuft, 3 Benachrichtigungen“).
- Kontextmenü: `role="menu"` / `menuitem` / `menuitemcheckbox`.
- Bei `prefers-reduced-motion: reduce` oder Einstellung `reduceMotion`:
  - Vergrößerung ohne Feder (direkt) oder aus.
  - Bounces durch sanftes Pulsieren der Deckkraft ersetzen.
  - Minimieren als kurzes Überblenden.
  - Auto-Hide als Fade statt Slide.
- Kontrast: Label- und Menütexte MÜSSEN mindestens WCAG AA erfüllen, auch über hellen und dunklen Hintergrundbildern (ggf. Deckkraft des Materials erhöhen).

## 19. Einstellungen (Konfigurationsobjekt)

```ts
interface DockSettings {
  tileSize: number;                 // 16–128, Standard 48
  magnification: boolean;           // Standard true
  magnifiedSize: number;            // tileSize–128, Standard 96
  magnificationRadius: number;      // in Kacheln, Standard 3
  position: "bottom" | "left" | "right";
  minimizeEffect: "genie" | "scale";
  minimizeToAppIcon: boolean;       // Standard false
  animateOpeningApps: boolean;      // Standard true
  autoHide: boolean;                // Standard false
  autoHideDelay: number;            // ms, Standard 200
  autoHideDuration: number;         // ms, Standard 350
  showIndicators: boolean;          // Standard true
  showRecentApps: boolean;          // Standard true
  theme: "system" | "light" | "dark";
  accentColor: string;              // Standard "#0a84ff"
  reduceMotion: "system" | boolean;
}
```

- Einstellungen werden persistiert (z. B. `localStorage`, gekapselt in einem austauschbaren Storage-Adapter).
- Ein kleines Einstellungs-Panel (eigenes Fenster in der Demo) MUSS alle Optionen live änderbar machen, inklusive Schieberegler für Größe und Vergrößerung.

## 20. Datenmodell und Zustände

```ts
type DockItemKind = "app" | "folder" | "file" | "minimizedWindow" | "trash" | "separator";

interface DockItem {
  id: string;
  kind: DockItemKind;
  name: string;
  icon: string;                     // URL oder Data-URI, eigene Grafik
  pinned: boolean;                  // für Apps
  running?: boolean;
  launching?: boolean;
  requestingAttention?: boolean;
  badge?: string | number | null;
  windows?: { id: string; title: string; minimized: boolean }[];
  folder?: {
    displayAs: "folder" | "stack";
    viewContentAs: "fan" | "grid" | "list" | "auto";
    sortBy: "name" | "dateAdded" | "dateModified" | "dateCreated" | "kind";
    items: { id: string; name: string; icon: string }[];
  };
  trashFull?: boolean;
  locked?: boolean;                 // Dateimanager, Papierkorb
}
```

### Zustandsautomat einer App-Kachel

```
not-running --click--> launching --(Ladezeit vorbei)--> running
running --quit--> not-running   (unpinned: Kachel wird entfernt)
running --requestAttention--> attention --activate/timeout--> running
```

### Dock-Interaktionszustand

```
idle | hovering | pressing | dragging(internal|external) | removingDrag
     | menuOpen | stackOpen | resizing | hidden | revealing | hiding
```

Übergänge MÜSSEN explizit modelliert werden (z. B. Reducer oder XState), damit sich Vergrößerung, Label, Menü und Auto-Hide nicht widersprechen.

## 21. Events / öffentliche API

```ts
interface DockProps {
  items: DockItem[];
  settings: DockSettings;
  onLaunch(appId: string): void;
  onActivate(appId: string): void;
  onQuit(appId: string, force: boolean): void;
  onReorder(orderedIds: string[]): void;
  onRemove(itemId: string): void;
  onPinChange(appId: string, pinned: boolean): void;
  onOpenWith(appId: string, files: File[]): void;
  onMoveToFolder(folderId: string, files: File[]): void;
  onTrash(files: File[]): void;
  onEmptyTrash(): void;
  onRestoreWindow(windowId: string): void;
  onSettingsChange(next: Partial<DockSettings>): void;
}

interface DockHandle {
  requestAttention(appId: string, repeat?: number): void;
  setBadge(itemId: string, badge: string | number | null): void;
  minimizeWindow(windowId: string, fromRect: DOMRect): Promise<void>;
}
```

## 22. Performance-Anforderungen

- Vergrößerung und Bounce MÜSSEN auf einem durchschnittlichen Laptop stabil mit 60 fps laufen (Messung über die Browser-Performance-Tools).
- Mausbewegungen werden pro Frame gebündelt (`requestAnimationFrame`), nicht pro `mousemove`-Event verarbeitet.
- Basis-Layout (Kachelmittelpunkte) wird nur bei Änderung der Items, Größe oder Position neu gemessen, nicht bei jeder Mausbewegung.
- `backdrop-filter` nur auf dem Dock-Hintergrund, Label und Menü – nicht auf jeder Kachel.
- `will-change: transform` nur während aktiver Animationen setzen.

## 23. Abnahmekriterien (Checkliste)

- [ ] Dock ist unten zentriert, schwebt leicht und zeigt transluzentes, unscharfes Material in Hell und Dunkel.
- [ ] Dateimanager ist immer links, Papierkorb immer rechts, Trenner zwischen App- und Dokumentbereich.
- [ ] Vergrößerung folgt dem Cursor flüssig mit Kosinus-Abfall, Icons wachsen nach oben über den Hintergrund hinaus, Dockbreite wächst mit, kein Flattern.
- [ ] Label erscheint sofort über dem vergrößerten Icon und wandert beim Überfahren mit.
- [ ] Klick auf nicht laufende App: Bounce, dann Laufindikator.
- [ ] `requestAttention` erzeugt höhere, wiederholte Sprünge, die per Klick enden.
- [ ] Badges werden korrekt angezeigt und skalieren mit.
- [ ] Umsortieren per Drag mit sich öffnender Lücke; Herausziehen zeigt „Entfernen“ und entfernt die Kachel.
- [ ] Kontextmenüs für App, Ordner, Trenner und Papierkorb mit allen Einträgen; „Beenden“ wird bei Alt zu „Sofort beenden“.
- [ ] Ordner öffnen sich als Fächer, Raster oder Liste mit passenden Animationen.
- [ ] Simuliertes Fenster minimiert sich per Trichtereffekt bzw. linearem Skalieren in eine Kachel und lässt sich wiederherstellen.
- [ ] Auto-Hide funktioniert inkl. Verzögerung und Tastenkürzel.
- [ ] Größe per Trenner ziehbar; Position links/rechts funktioniert vollständig.
- [ ] Tastaturbedienung und Screenreader-Beschriftungen vorhanden.
- [ ] `prefers-reduced-motion` wird respektiert.
- [ ] Keine Apple-Assets, -Schriften oder -Markennamen im UI.
