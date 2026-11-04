# Prüfung der Veröffentlichungsreife

Stand: 4. November 2026. Geprüft wurde der aktuelle Arbeitsstand einschließlich bereits vorhandener, nicht committeter Änderungen.

Ergebnis: Build und vorhandene automatisierte Prüfungen bestehen. Für eine uneingeschränkte öffentliche Freigabe bleiben offene Punkte. Für den App Store ist der geprüfte Stand noch nicht bereit. Ein erfolgreicher Build bestätigt keine vollständige Sicherheit oder Funktionsfähigkeit auf einem Gerät.

## Bestätigte Befunde

### 1. Hoch, App Store: Privacy-Manifest fehlt auch in der IPA

`ProfileStore.swift:16`, `LibraryStore.swift:52` und zahlreiche `@AppStorage`-Eigenschaften verwenden UserDefaults. Weder im Quellbaum noch in der frisch erzeugten IPA befindet sich eine `PrivacyInfo.xcprivacy`.

Apple verlangt für diese API eine Erklärung des Verwendungszwecks im Privacy-Manifest. Die lokale Speicherung eigener Einstellungen entspricht voraussichtlich dem Grund CA92.1; vor Einreichung müssen alle tatsächlich verwendeten API-Kategorien geprüft und das Manifest im ausgelieferten Bundle verifiziert werden.

Quelle: [Apple: Required reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api), [Apple: TN3183](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest).

### 2. Mittel, Sicherheit: Domainprüfung schließt private Netzwerkziele nicht aus

`SourceModels.swift:216–242` prüft Namen, HTTPS, Ports und Hostfreigaben. `SourceNetwork.swift:38` überlässt die DNS-Auflösung anschließend URLSession. Private, Loopback- und Link-Local-Zieladressen werden nicht anhand der tatsächlich verbundenen Adresse ausgeschlossen. Die Redirect-Prüfung verwendet dieselbe namensbasierte Policy.

Reproduktion mit dem unveränderten `SourcePolicy`-Code in einem temporären Swift-Programm: `https://10.0.0.1.nip.io/` wird mit passender Hostfreigabe akzeptiert. Die DNS-Abfrage dieser Domain ergab in der Prüfumgebung `10.0.0.1`. Auch `127.0.0.1.nip.io` wurde von der Policy akzeptiert; dessen DNS-Auflösung war hier nicht verfügbar. Es wurde keine Verbindung zu einem internen Dienst aufgebaut.

Eine bewusst installierte bösartige Erweiterung kann damit interne HTTPS-Ziele anfordern und erhaltene Antworten über einen weiteren erlaubten Host weitergeben. Das setzt weiterhin eine erfolgreiche TLS-Zertifikatsprüfung und erlaubten Netzwerkzugriff auf dem Gerät voraus; beliebige interne HTTP-Dienste sind damit nicht erreichbar. Kein nachgewiesener Zugriff auf lokale Dateien oder Zugangsdaten.

Abhilfe: Private und reservierte Adressbereiche für alle Verbindungen und Redirects ausschließen. Die Prüfung muss an das tatsächliche Verbindungsziel gebunden sein; eine vorgelagerte DNS-Abfrage allein verhindert DNS-Rebinding nicht. Mit einem kontrollierten HTTPS-Ziel und auf iOS verifizieren.

### 3. Mittel, Profile: NSFW-Freigabe gilt über Profilgrenzen hinweg

`SumiApp.swift:6` hält einen gemeinsamen SourceStore. `SourceStore.swift:8,20,55–66` speichert `nsfwSourceIDs` gemeinsam in `sources-v1.json`. Ein Wechsel des Profils erzeugt einen neuen LibraryStore, übernimmt aber den gemeinsamen NSFW-Zustand.

Folge: Wird NSFW in Profil A aktiviert, ist es auch in Profil B aktiviert. Die Oberfläche verspricht in `ProfilesView.swift` eigene Einstellungen pro Profil. Bibliotheken und reguläre Leseeinstellungen sind in den vorhandenen Tests getrennt; diese Inhaltsfreigabe ist es nicht. Die Profile besitzen zudem keine Zugriffssperre und sollten nicht als Kinderschutz beworben werden.

Abhilfe: Inhaltsfreigaben pro Profil speichern, standardmäßig deaktivieren und bei einem Profilwechsel laufende Katalog-/Leseanfragen entsprechend neu bewerten.

### 4. Hoch, App Store: In-App-NSFW-Aktivierung und Erweiterungsmodell klären

`SourceViews.swift:395` bietet einen Schalter direkt in der App. `extensions/mangadex/adapter.template.js` schließt bei Aktivierung ausdrücklich `erotica` und `pornographic` ein. Die Erweiterungen sind separat installierbar, nicht im App-Bundle enthalten.

Apples Richtlinie 1.2 erlaubt beiläufige NSFW-Inhalte webbasierter UGC-Dienste nur unter Bedingungen und nennt die Aktivierung über die Website. Der hier angebotene In-App-Schalter passt nicht zu dieser Bedingung. Die heruntergeladenen JavaScript-Erweiterungen sind außerdem anhand der Regeln 2.5.2/4.7 zu bewerten. WebKit-Ausführung allein garantiert keine Zulässigkeit. Das ist ein erheblicher Review-Risikopunkt, keine Behauptung einer bereits erfolgten Ablehnung.

Abhilfe: Für eine App-Store-Fassung Inhalts- und Erweiterungskonzept anhand der einschlägigen Regeln ausarbeiten; Altersfreigabe und Rechte an angebotenen Inhalten müssen zur tatsächlichen Nutzung passen.

Quelle: [Apple App Review Guidelines, 1.1.4, 1.2, 2.5.2 und 4.7](https://developer.apple.com/app-store/review/guidelines/).

### 5. Mittel, App Store: Datenschutzerklärung in der App fehlt

Die Einstellungen in `CollectionScreens.swift` enthalten keinen Link auf eine Datenschutzerklärung; auch die übrigen geprüften Views enthalten keinen solchen Link. Quellen erhalten zumindest IP-Adresse, Suchanfragen und angeforderte Titel/Kapitel. Der Installationsdialog erklärt einen Teil davon bereits.

Apple verlangt einen leicht erreichbaren Link innerhalb der App und in den Store-Metadaten. Die Store-Metadaten und eine eventuell extern vorhandene Erklärung wurden nicht geprüft.

Abhilfe: Eine zutreffende Erklärung bereitstellen und in den Einstellungen verlinken; lokale Speicherung, Drittquellen und Löschmöglichkeiten erklären.

Quelle: [Apple App Review Guidelines, 5.1.1(i)](https://developer.apple.com/app-store/review/guidelines/#privacy).

## Vor Freigabe auf Geräten zu prüfen

- **PDF-Ressourcenverbrauch:** `LibraryStore.swift:177–203` kopiert PDFs ohne Größenlimit und parst/renderiert anschließend auf dem MainActor. Ein großes oder aufwendig aufgebautes PDF kann Speicherplatz verbrauchen und die Oberfläche blockieren; während synchroner PDFKit-Arbeit greift die Abbruchprüfung nicht. Größen-/Speicherplatzgrenzen und schwierige PDFs testen. Ein Absturz wurde hier nicht reproduziert.
- **Lange Bildkapitel:** Jedes dekodierte Seitenbild darf bis zu 32 Millionen Pixel umfassen, ungefähr 128 MB bei vier Bytes pro Pixel. `SourceImage` hält das Bild im View-State; für vertikales Lesen gibt es kein explizites gemeinsames Speicherbudget oder Freigabeverhalten für nicht sichtbare Bilder. LazyVStack allein belegt keine beschränkte Speichernutzung. Langes Scrollen, große Webtoon-Streifen, schneller Kapitelwechsel und Speicherdruck auf älteren iPhones messen. Ein Speicherabsturz wurde hier nicht reproduziert.
- **WebKit-Laufzeit:** Bösartige Erweiterungen mit Endlosschleifen, sehr großen Ergebnissen, Navigation und Request-Fluten auf iOS testen. Die Node-Tests ersetzen die tatsächliche WKWebView-Sandbox nicht.
- **Alltag:** Neuinstallation und Update bestehender Daten, Profilwechsel, Offline-/Timeout-Verhalten, Hintergrund/Vordergrund, iPad, VoiceOver und iOS 17 prüfen. Diese Geräteprüfungen wurden in dieser Windows-/WSL-Sitzung nicht durchgeführt.

## Erfolgreiche Prüfungen

- `python3 scripts/test_reading_position.py`
- `python3 scripts/test_library_import.py`: Importablauf mit Testdoubles, Cleanup, Abbruch, Persistenz, Profiltrennung, Quellmodelle und Redirect-Regeln.
- `python3 scripts/test_source_repository.py`: generiertes Repository, SHA-256 und JavaScript-Ablauf Suche → Kapitel → Seiten.
- `node scripts/test_mangadex_source.mjs`: deutsche und englische Adapter, Filter, Pagination, Integrität und Fehlerfälle; keine vollständige Live-Service-Prüfung.
- `xtool dev build --configuration release --ipa`: erfolgreich.
- `python3 scripts/verify_build.py --expect-glass native --ipa`: arm64-Mach-O, iOS-17-Minimum, Bundle-Metadaten, Grafiken und Archiv erfolgreich geprüft.
- Geprüfte IPA enthält keine Privacy-Manifeste; Version 1.0.0, Build 1.

## Positive Sicherheitsmerkmale und Grenzen

Keine externen Swift-Paketabhängigkeiten im Package-Manifest. Kein offensichtliches eingebettetes produktives Secret in der durchsuchten Projektquelle gefunden. Keine vollständige Git-Historien- oder Toolchain-Prüfung.

Erweiterungen verwenden eine nichtpersistente WKWebView mit CSP und eingeschränkter Nachrichtenbrücke. Netzwerkzugriffe besitzen Größen-, Zeit-, Request- und Parallelitätslimits; HTTPS und Hostfreigaben werden auch bei Redirects geprüft. Cookie- und Credential-Speicher sind deaktiviert. Skripte werden per SHA-256 geprüft; Updates benötigen eine erneute Installation. Dieser Hash bestätigt Integrität gegenüber dem Repository, nicht die Vertrauenswürdigkeit seines Betreibers.

Es wurde kein kritischer Zugriff auf beliebige Dateien oder eine native Codeausführung nachgewiesen. Das ist keine umfassende Sicherheitszertifizierung. Produktivcode wurde bei dieser Prüfung nicht verändert; die IPA wurde neu gebaut und dieser Bericht hinzugefügt.
