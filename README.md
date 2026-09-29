# Footprint

En macOS-app i Swift för ansökningar, projekt, publikationer, undervisning, CV och kalender.

## Mappar

| Mapp | Vad den är | Behövs? |
|---|---|---|
| `Sources/Footprint` | Appens kod, och i `Resources` de filer som följer med appen (exportskript, ISSN-förkortningar). Tidskriftskatalogen läses från `Application Support/Footprint/Reference`. | Ja |
| `Tests/FootprintTests` | Omkring 620 automatiska tester som körs vid varje bygge. | Ja |
| `TestData` | 13 JSON-filer med påhittade poster (samma filnamn och samma fält som appens riktiga register, men fiktiva namn, organisationer, projekt och möten). Testerna kontrollerar att nya fält inte gör att befintliga poster slutar gå att läsa. | Ja |
| `Scripts` | Byggskript (`package_app.sh`), appens inställningar (`Footprint-Info.plist`) och hjälpskript. | Ja |
| `.github/workflows` | Automatiskt bygge och tester på GitHub. | Ja |

## Bygga på Macen

```
FOOTPRINT_SKIP_TESTS=1 zsh Scripts/package_app.sh
```

Appen hamnar i `~/Applications/Footprint.app`. Testerna har redan körts på GitHub, därför hoppas de över här.
Testerna kan inte längre skriva i den riktiga databasen (F34), men det är ändå onödigt att köra dem två gånger.

## Data

Det här förrådet innehåller ingen riktig data. Den riktiga databaskopian (`data_snapshot`) och de riktiga testposterna ligger i ett separat, privat förråd, `footprint-data`. Där körs provkörningen mot riktig data (`SnapshotTrialRunTests`); här hoppas de testerna över eftersom `data_snapshot` saknas.

Appens data ligger i `~/Library/Application Support/Footprint`.
Exporten till Google Drive är avstängd (`FootprintExportEnabled` i `Scripts/Footprint-Info.plist`).
