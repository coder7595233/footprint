# Footprint – regler för Claude

- Jag kodar inte själv. Förklara alltid ändringar på enkel svenska, aldrig i kodtermer.
- Varje pull request ska ha en beskrivning med: vad som ändrats, varför,
  vad som kan gå fel, och en kort lista med vad jag ska prova i appen efteråt.
- Det här förrådet är offentligt. Lägg aldrig in riktig data här: inga riktiga namn,
  e-postadresser, telefonnummer, ORCID, personnummer, diarienummer, sökvägar från
  min dator eller utdrag ur databasen – inte heller i tester, kommentarer eller
  beskrivningar av pull requests. Testdata i TestData/ är påhittad och ska förbli det.
- Den riktiga datan ligger i det privata förrådet footprint-data (data_snapshot/ och
  riktiga TestData/). Ändringar i datamodellen ska provköras mot riktig data där innan
  PR öppnas: kör arbetsflödet "Provkörning mot riktig data" i footprint-data med
  PR-grenen, och rapportera antal poster före och efter (raderna som börjar med
  SNAPSHOT: i loggen). Klistra inte in riktiga namn eller värden i PR:en, bara antal.
- Ändra aldrig filerna i data_snapshot/ i footprint-data.
- Radera aldrig funktioner, filer eller data utan att fråga först.
- Appen är en macOS-app i Swift och kan inte byggas här. Säg tydligt vad jag
  behöver bygga och prova på min Mac.
