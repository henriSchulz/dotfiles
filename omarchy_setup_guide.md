# Automatisierte Linux-Einrichtung (Omarchy / Hyprland)

Dieses Dokument fasst die Methode zur idempotenten Systemkonfiguration zusammen, basierend auf dem Video "You installed Omarchy, Now What?" von Typecraft, sowie zusätzlichen Best Practices für Themes und Plugins.

## 1. Grundprinzip: Idempotenz
Das Kernkonzept ist die Erstellung **idempotenter** Shell-Skripte. Das bedeutet, die Skripte können beliebig oft ausgeführt werden, ohne das System zu beschädigen, Fehler zu werfen oder Einträge doppelt vorzunehmen. Wenn etwas bereits installiert oder konfiguriert ist, überspringt das Skript diesen Schritt einfach.

## 2. Modulare Software-Installation
Anstatt alle Programme manuell zu installieren, werden kleine, spezialisierte Skripte geschrieben:
* **Einzelne Skripte:** Für jedes Programm (z. B. `install_ghostty.sh`) wird ein eigenes Shell-Skript angelegt.
* **Automatisierung:** Der Paketmanager (z. B. `yay`) wird mit Flags wie `--noconfirm` (keine Bestätigung nötig) und `--needed` (nur installieren, wenn noch nicht vorhanden) aufgerufen.
* **Master-Skript:** Ein übergeordnetes Skript (`install_all.sh`) ruft alle Einzelskripte nacheinander auf. Dies sorgt für Ordnung und einfache Wartbarkeit.

## 3. Dotfiles-Verwaltung mit GNU Stow
Persönliche Konfigurationsdateien (Dotfiles) für Programme (Neovim, Terminals, etc.) werden zentral in einem Git-Repository gespeichert.
* **Funktionsweise:** Ein Skript klont das Repository und nutzt das Tool **GNU Stow**.
* **Symlinks:** Stow erstellt automatisch symbolische Verknüpfungen (Symlinks) vom lokalen Repository in die jeweiligen Systemordner (z. B. `~/.config/`).
* **Vorbereitung:** Das Installationsskript löscht vorher eventuell vorhandene Standard-Configs des Betriebssystems, um Dateikonflikte mit den Symlinks zu vermeiden.

## 4. Idempotentes Überschreiben von System-Konfigurationen
Original-Konfigurationsdateien des Systems (wie die Standard-Hyprland-Config von Omarchy) werden nicht direkt bearbeitet.
* **Override-Datei:** Es wird eine eigene Datei (z. B. `omarchy_overrides.conf`) erstellt, die nur die individuellen Anpassungen (z. B. Bildschirmskalierung oder Keybinds) enthält.
* **Automatisches Einbinden:** Ein Skript prüft mithilfe von `grep`, ob der Befehl zum Einbinden (`source /pfad/zur/overrides.conf`) bereits am Ende der Hauptkonfigurationsdatei steht.
* **Ergänzung:** Nur wenn dieser Befehl fehlt, fügt das Skript die `source`-Zeile am Ende der Hauptdatei hinzu. Das System nutzt so die Standardeinstellungen plus die eigenen Overrides.

## 5. Nahtlose Übertragung auf neue Hardware
Durch dieses modulare Setup wird der Wechsel auf einen neuen Rechner extrem einfach (im Video an einem Framework-Laptop demonstriert):
1. Basis-Betriebssystem installieren.
2. Das eigene Git-Repository herunterladen.
3. Das Master-Skript ausführen.
> **Ergebnis:** Das System versetzt sich vollautomatisch in den exakt gewünschten, maßgeschneiderten Zustand.

## 6. Erweiterung: Themes und Plugins (Best Practices)
Diese Methodik lässt sich hervorragend auf die visuelle und funktionale Anpassung des Systems ausweiten:
* **Themes als Dotfiles:** Farbpaletten oder CSS-Dateien (z. B. für Waybar, Rofi) werden exakt wie andere Configs per GNU Stow verlinkt.
* **Themes per Override:** Theme-Änderungen lassen sich als `source`-Befehl in die `overrides.conf` auslagern, anstatt die Original-Theme-Datei zu modifizieren.
* **Plugins installieren:** Hyprland-Plugins oder Erweiterungen werden als eigenes Skript via `yay` oder Plugin-Manager (z. B. `hyprpm`) ohne Nutzerinteraktion installiert.
* **Achtung bei dynamischen Theme-Switchern:** Wenn Systemtools Themes "on-the-fly" ändern, können die schreibgeschützten Symlinks von GNU Stow zu Fehlern führen. In solchen Fällen ist es besser, Theme-Anpassungen über die Override-Methode abzuwickeln.
* **Plugin-Updates absichern:** Ein Befehl wie `hyprpm update` sollte in das Skript integriert werden, da bestimmte Plugins (wie bei Hyprland) bei jedem Systemupdate neu kompiliert werden müssen.
