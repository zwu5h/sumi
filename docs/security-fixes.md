# Sicherheitskorrekturen – 4. November 2026

Diese Änderungen bauen auf dem vorhandenen Arbeitsbaum auf. Der frühere Prüfbericht in release-readiness.md beschreibt den Zustand vor diesen Korrekturen.

## Behoben

- Der Erweiterungscode läuft in einem eigenen Funktionskörper. Ein früher Return umgeht die aufrufende Prüfung nicht mehr. Suche und Filter haben eine Ergebnisgrenze; Swift erzwingt zusätzlich maximal 4.000.000 UTF-8-Bytes. Auch Bridge-URLs werden begrenzt.
- Beschädigte Bibliotheks- und Profilarrays werden eintragsweise gelesen. Die unveränderten Originalbytes bleiben unter `<Schlüssel>.recovery` in derselben Defaults-Suite erhalten; weitere unterschiedliche beschädigte Stände erhalten eigene Sicherungsschlüssel. Unlesbare Lesestanddaten werden ebenfalls gesichert. Ein beschädigter Quellenzustand wird vor späteren Änderungen als separate Datei gesichert; scheitert die Sicherung, bleiben Schreibzugriffe gesperrt.
- App-PDFs, Vorschaubilder und sources-v1.json werden ohne Überschreiben aus Documents nach Application Support/Sumi verschoben. Bibliotheken, Profil-Suites und IDs bleiben bestehen. Bei Konflikten bleibt auch die alte Datei erhalten. Fehlgeschlagene Migrationen werden angezeigt. Dateifreigabe des gesamten Containers ist deaktiviert; einzelne PDFs können über Export PDF geteilt werden.
- Dateipfade aus dem Importindex müssen einfache PDF-Dateinamen sein. Die Löschfunktion akzeptiert nur registrierte Importe. Das Löschen der Quelldatei durch einen manipulierten PDF-Dateinamen wird damit verhindert.
- Importkopien werden zunächst in .imports abgelegt. Der nächste Start bereinigt im Profiljournal vermerkte unvollständige Kopien; bereits validierte und final verschobene PDFs werden anhand ihres gespeicherten Importdatensatzes wieder registriert. Symlinks werden beim Kopieren aufgelöst. Ein transaktionaler Schutz gegen jeden Stromausfall ist damit nicht zugesichert: UserDefaults und Dateisystem sind weiterhin getrennte Speicher.
- Kapitelnummern werden vor Verwendung normalisiert; die Remapping-Subtraktion prüft ihren Wertebereich. Numerische Kapitelpositionen werden beim ersten Erhalt stabiler IDs übertragen.
- Hexadezimale IPv4-Schreibweisen werden zurückgewiesen. Der explizite MangaDex-Inhaltsfilter wird auch auf Antworten angewendet. Der dokumentierte Standard für Quelleninhalte bleibt erhalten; es wird kein neuer NSFW-Schalter eingeführt.
- PrivacyInfo.xcprivacy mit UserDefaults-Grund CA92.1 ist Bestandteil des App-Bundles. Die Einstellungen enthalten eine lokale Datenschutzerklärung. Der Paketcheck kontrolliert Manifest, deaktivierte Containerfreigabe und Mach-O-SDK; --app-store verlangt zusätzlich SDK 26+.

## Regressionstests

`python3 scripts/test_library_import.py` führt zusätzlich SecurityRegressionChecks.swift aus: Migration und Dateikonflikte, beschädigte Indizes mit Byte-Sicherung, gesperrte Dateinamen, Kapitelmigration/Überlauf und unterbrochene Importe. SourceChecks prüft UTF-8-Grenzwerte sowie hexadezimale IPs. `node scripts/test_source_runtime.mjs` führt den produktiven Wrapper mit frühen Returns, übergroßen Such-/Filterergebnissen und den generierten MangaDex-Adaptern aus. Die Adaptertests prüfen Antworten bei explizitem Safe-Filter trotz allowNSFW=true.

Ergebnis dieser Sitzung: Die genannten Tests, test_reading_position.py, test_source_repository.py und build_mangadex_repository.py --check bestanden. Der zusätzliche MangaDex-Livetest erreichte 43 Kapitel, 37 Seiten-URLs und ein erfolgreich geladenes Bild. Native und Fallback-Release-Builds samt IPA-Paketprüfung bestanden. Das ausgelieferte Manifest und der deaktivierte Containerzugriff wurden im Archiv verifiziert. Die SDK-Angabe bleibt 17.0; --app-store darf diese IPA deshalb nicht als einreichungsfähig akzeptieren. Tests verwenden für PDFKit und SwiftUI portable Testdoubles; Geräteprüfungen bleiben offen.

## Offen

- DNS-/Rebinding-sicheres Ausschließen privater und reservierter tatsächlicher Verbindungsadressen. Ein syntaktischer Hostcheck reicht dafür nicht aus; HTTPS/TLS- und Redirect-Prüfungen bleiben aktiv.
- Globale Bildspeicherbudgets, schwierige PDFKit-Dateien, Abbruchlatenz, WebKit-Endlosschleifen und große IPC-Nachrichten auf realen iPhones/iPads. Hosttests ersetzen weder PDFKit noch WebKit auf iOS.
- Mehrere gleichzeitige LibraryStore-Instanzen für dieselbe Suite können weiterhin veraltete Gesamtzustände schreiben. Die tatsächliche gleichzeitige Erreichbarkeit im ausgelieferten Szenenablauf wurde nicht belegt.
- Profile sind keine Zugriffssperre. Installierte Quellen werden bewusst gemeinsam verwaltet; ihre Repositoryidentität wird nach einer Entfernung nicht dauerhaft an gespeicherte Titel gebunden. Bereits vor dem Update lokal manipulierte Quelldateien lassen sich durch eine reine Speichermigration nicht als solche erkennen.
- App-Store-Signierung, zulässige Toolchain/SDK-Metadaten, externe Datenschutz-URL und Store-Angaben sowie Einordnung des Erweiterungs-/Inhaltsmodells und Nutzungsrechte. Ein erfolgreich geprüftes Sideload-IPA ist keine App-Store-Freigabe.
- Recovery-Sicherungen haben bislang keine eigene Wiederherstellungsoberfläche. Sie werden bewusst nicht automatisch gelöscht.
