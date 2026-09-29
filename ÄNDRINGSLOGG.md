# Footprint – ändringslogg

Ändringar i appens kod, inte datarättelser. Ersätter Google-dokumentet "Footprint – ändringslogg" från 2026-09-27.
Loggen uppdateras i samma pull request som ändringen. Status: Öppen, Pågår, Klar (med datum och pull request).

## Arbetssätt

- Koden ligger på GitHub. Varje ändring görs på en gren och blir en pull request.
- GitHub bygger appen och kör alla tester vid varje pull request.
- Appens ägare bygger på Macen med `FOOTPRINT_SKIP_TESTS=1 zsh Scripts/package_app.sh`, provar enligt listan i pull requesten och slår ihop.
- Ändringar i datamodellen provkörs mot en kopia av `data_snapshot` innan pull requesten öppnas, med antal poster före och efter.

## Appens konventioner

- Fält visar appens språk; man byter språk för att redigera det andra. Inga dubbla rutor i formulär.
- Fält som behöver uppmärksamhet får en streckad ram i en betydelsefärg med förklaring vid muspekaren.
- Alla kvalitetsfrågor samlas i vyn Data. Varje rad har Dölj och Visa, och hela raden öppnar posten.
- Ändringar går att ångra. Borttagning bekräftas i dialog.
- Kopplingar mellan poster lagras som id; namnet finns kvar som visningstext.

## Klart

| Nr | Område | Ändring | Status |
|---|---|---|---|
| F1 | Bilagor | Filen heter postens id; underhållssteg döper om och slår ihop dubbletter. | Klar 2026-09-27 |
| F1c | Bilagor | Appen och bilagereparationen gav filerna olika namn, så alla PDF:er tappade kopplingen. Samma namnregel överallt, och gamla filnamn hittas. | Klar 2026-09-28 (#3) |
| F2, F3 | Konferensbidrag | Status räknas från utfall och datum; författarsträngar skrivs om från listan. | Klar 2026-09-27 |
| F4, F5, F7 | Undervisning | Program, kurser och kurskoder med giltighet; nivå på programrader; kurskodshistorik. | Klar 2026-09-28 (omgång 2c) |
| F8 | Granskningsuppdrag | Granskningsomgång (R1–R9). | Klar 2026-09-27 |
| F9–F11 | Nya poster, datum, ORCID | "New project" sparas inte kvar; omöjlig dag justeras; ORCID-format. | Klar 2026-09-27 |
| F12 | Språk | Data-vyn flaggar saknade översättningar för alla tvåspråkiga posttyper. | Klar 2026-09-28 (#3), fortsätter i omgång 4 |
| F13 | Kopplingar | Undervisning, tidskrifter i publikationer och granskningar, projekt i konferensbidrag kopplas med id. | Delvis klar 2026-09-28 (#3), resten i omgång 5 |
| F14–F16a, F17, F18, F22–F28 | Diverse | Se Google-dokumentet från 2026-09-27. | Klar 2026-09-27 |
| F19 | Kontroll vid sparning | Varning "Sparat, men kontrollera: …" när en sparning ger ett nytt felaktigt värde. Sparningen stoppas aldrig (beslut 2026-09-28). | Klar 2026-09-28 (#3), fler kontroller i omgång 4 |
| F29 | Kodhygien | Varningen om `document.filename` åtgärdad. | Klar 2026-09-28 (#2) |
| F30 | Sparspärr | Sparning som tömmer ett register stoppas. | Klar 2026-09-27 |
| F32, F33 | Kalendern | Dagordning och protokoll går att använda; filterlistorna tar emot klick. | Klar 2026-09-28 (#2) |
| F34 | Tester | Tester når aldrig den riktiga databasen; sparning som byter ut de flesta posterna i ett register stoppas. | Klar 2026-09-28 (#2) |
| F35 | Bygge | GitHub bygger och testar vid varje pull request; appen kan signeras; Drive-exporten avstängd. | Klar 2026-09-28 (#2, #3) |

## Omgång 4 – klar 2026-09-28 (#4)

| Nr | Område | Ändring | Status |
|---|---|---|---|
| F36 | Kalendern | Borttagning i kalendern går snabbt. | Klar 2026-09-28 (#4) |
| F12b | Språk | "Saknade översättningar" som egen sektion: en rad per fält, svenska till vänster och engelska till höger, redigerbart direkt. | Klar 2026-09-28 (#4) |
| F19b | Kontroll vid sparning | ORCID-kontrollsiffra, sluttid före starttid, beslut efter kongressen, kopplingar som pekar på poster som inte finns. | Klar 2026-09-28 (#4) |
| F1b | Bilagor | Bilagan visar en etikett från posten; exporten får en bilageförteckning. | Klar 2026-09-28 (#4) |
| F37 | Statistik | Statistikområdet Doktorander tas bort; statistiken visas under Doktorander. | Klar 2026-09-28 (#4) |
| F38 | Offentlig kod | Personuppgifter bort ur koden; första forskaren blir "jag"; tidskriftslistan läses från Application Support. | Klar 2026-09-28 (#4) |

## Omgång 4b – klar 2026-09-28 (#5)

| Nr | Område | Ändring | Status |
|---|---|---|---|
| F36b | Kalendern | Borttagning av uppgifter går samma snabba väg som möten och resor. | Klar 2026-09-28 (#5) |
| F12c | Språk | Listan "Saknade översättningar" räknas om bara efter en ändring, inte vid varje uppritning. | Klar 2026-09-28 (#5) |
| F19c | Kontroll vid sparning | Datum i fel ordning varnas även för utlysningar med status "Att söka". | Klar 2026-09-28 (#5) |
| F42 | Data-vyn | Efter en sparning laddades alla listor i Data-vyn om två gånger (en gång när posten ändrades, en gång när den skrivits till disken). Nu en gång. | Klar 2026-09-28 (#5) |
| F42b | Data-vyn | Efter en sparning laddas bara de öppna sektionerna om. Hopfällda sektioner behåller sin siffra och laddas om när de öppnas. | Klar 2026-09-28 (#5) |
| F41 | Tidslogg | Sparning, borttagning i kalendern och kontrollen efter sparning skriver sin tid i `performance_diagnostics.log` när de tar mer än 12 ms. | Klar 2026-09-28 (#5) |

## Omgång 5 – klar 2026-09-28 (#6)

| Nr | Område | Ändring | Status |
|---|---|---|---|
| F16 | Personer | En person har ett aktuellt namn och tidigare namn. När namnet ändras sparas det gamla som tidigare namn med dagens datum. Poster behåller namnet de skrevs med och hittar ändå rätt person. På forskarkortet visas "Tidigare namn" (med datum) och "Andra stavningar" var för sig, och en rad kan flyttas mellan dem. Att varje post också sparar vilken person den gäller görs som en egen del. | Klar 2026-09-28 (#6) |
| F16b | Personer | Forskarkortet använder ord i stället för symboler. Varje tidigare namn och stavning har en rullgardin "Välj…" med "Är ett tidigare namn" / "Är en stavning", "Gör till aktuellt namn" och "Ersätt med aktuellt namn i alla poster och ta bort…". Den sista visar hur många poster som skriver namnet så, frågar, ger posterna det aktuella namnet och tar bort det gamla; den ersätter papperskorgen (beslut 2026-09-28). Plustecknen heter "Lägg till tidigare namn" / "Lägg till annan stavning", och papperskorgarna vid anställningar, utbildningar och affilieringar heter "Ta bort". Går att ångra. | Klar 2026-09-28 (#6) |
| F13c | Data-vyn | Ny sektion "Namn att koppla": namn som står i ansökningar, projekt, möten, uppgifter, publikationer, konferensbidrag, doktorander och undervisning men inte hör ihop med någon forskare. Varje namn visas en gång med hur många poster som använder det och var. Namnet kan kopplas till en befintlig forskare (det blir då ett av forskarens namn), bli en ny forskare eller döljas. Går att ångra. | Klar 2026-09-28 (#6) |
| F13b | Kopplingar | Personer som hittills bara sparats med namn får också en fast koppling till forskaren: medsökande i ansökningar, medarbetare i projekt, författare och korresponderande författare i publikationer, deltagare i uppgifter och möten. Namnen står kvar som de är skrivna; ett namn som inte hör till någon forskare får ingen koppling. Befintliga poster kopplas en gång vid nästa start (säkerhetskopia tas först, och inget ändras om antalet poster eller något namn skulle ändras). Byter en forskare namn behålls kopplingen; tas forskaren bort försvinner kopplingen; slås två dubbletter ihop flyttas kopplingen. "Huvudsökande" och "projektledare" avgörs i första hand av kopplingen. Filtret "per projekt" i ansökningslistan fungerar nu även när appen visas på engelska. | Klar 2026-09-28 (#6) |

## Offentlig version

| Nr | Område | Ändring | Status |
|---|---|---|---|
| F47 | Offentlig kod | Inga namn på organisationer eller orter i koden. Standardprogrammet heter "Programmet", fakulteten är tom och hemregionen och lönekalkylens organisation väljs aldrig utifrån namnet; lönekalkylens standardmall har inga egna kostnadssatser. De värden som tidigare var inbyggda sparades i datan av versionen före denna. Kolumnen för lärosätets diarienummer i ansökningsexporten heter nu "Diarienummer hos lärosätet". Kontaktadressen i exporten av pedagogiska meriter är borttagen (ansökan skickas via ett webbformulär); en sparad adress läses in utan fel och används inte. | Klar 2026-09-29 (första offentliga versionen) |

## Omgång 9 – 2026-09-29

| Nr | Område | Ändring | Status |
|---|---|---|---|
| F49 | Media | Media-PDF:er som bara låg i den äldre mappen "Media Appearance Files" hittades inte, eftersom appen bara letade i "Media Appearance PDFs". Nu letar appen även där, och vid nästa start kopieras filen till "Media Appearance PDFs" under postens id. Originalet ligger kvar. Datakvalitet visar "Saknar länkad PDF-fil" för mediaposter vars PDF inte hittas; tidigare kontrollerades bara publikationer och granskningsintyg. | Pågår |
| F50 | Undervisning | Listan över undervisningsuppdrag markerar vald rad som övriga listor (helt blå). Uppdrag som bara delvis är bekräftade i Retendo får en röd kant till vänster i stället för gul bakgrund, och kanten syns även när raden är vald. | Pågår |
| F51 | Organisationer | "Kopplade forskare" visas för alla organisationer, inte bara lärosäten. | Pågår |
| F52 | Organisationer | Enhetsrutan har fältrubriken till vänster om fältet (svenskt namn, engelskt namn, ort). Under rutan listas forskarna vars affiliering, anställning eller utbildning pekar på enheten; ett klick på namnet öppnar forskaren. | Pågår |

## Omgång 8 – offentlig version

- Engångsrättningen av en enskild granskning är borttagen. Granskningar sparas som de är skrivna och hittar sin organisation via den fasta kopplingen.
- Kryssrutan för ansökningar utan overhead i lönekalkylen är borttagen. I stället har varje anslagsgivare en OH-regel på organisationens sida (se nedan).
- Den gamla kryssrutan tas bort en gång vid start. Ingen regel sätts automatiskt, eftersom rutan inte angav vilken finansiär den gällde; regeln fylls i på finansiären.
- OH beror nu på både medelsförvaltaren och anslagsgivaren. Varje anslagsgivare har "OH-regel" med tre val: "Förvaltarens fulla OH" (standard), "Högst … %" och "Ingen OH", och rutan "Taket inkluderar lokalkostnad" (en anteckning; appen räknar inte lokalkostnad för sig). Under "Undantag per medelsförvaltare" kan man lägga rader av typen "När [medelsförvaltare] förvaltar: …" som gäller i stället för grundregeln när just den medelsförvaltaren förvaltar ansökan.
- Varje medelsförvaltare har fältet "Förvaltarens fulla OH (%)". Har organisationens lönekalkyl OH-perioder används de i stället, och då står det under fältet. Saknar ansökan medelsförvaltare, eller är inget ifyllt på den, används OH i lönekalkylen för ansökningar som förut.
- I ansökan, under lönebudgeten, står till exempel "OH: 15 % (förvaltarens 20 %, anslagsgivarens tak 15 %)", och när anslagsgivaren betalar mindre än förvaltarens fulla OH även "Behov av samfinansiering: N kr" (skillnaden räknad på samma lönesumma). Raden visas när "Inkluderar OH" är ikryssad; utan kryss räknas lönebudgeten som förut utan OH. Anslagsgivaren och medelsförvaltaren hittas via ansökans fasta kopplingar. Inga värden gissas utifrån namn.
- Fältet "Max OH (%)" som fanns en kort tid ersätts av OH-regeln. Ett ifyllt värde flyttas en gång vid start: ett tal blir "Högst tal %", 0 blir "Ingen OH", tomt blir "Förvaltarens fulla OH". Äldre data går fortfarande att läsa.
- Lönetabellen på organisationens sida visar nu alltid hela kostnaden med overhead.

## Omgång 7 – klar 2026-09-29 (första offentliga versionen)

### Snabbare Datakvalitet och kalender

| Nr | Område | Ändring | Status |
|---|---|---|---|
| F45 | Data-vyn | Att trycka Dölj eller Visa på en varning frös appen i ungefär 0,6 sekunder per klick. Hittat: varje klick skrev om alla inställningar och alla 1 800 möten direkt (cirka 0,17 s), kastade listorna över översättningar och namn så att de byggdes om, och varje rad frågade "är den dold?" på ett sätt som gick igenom alla inställningar. Nu sparas klicket i bakgrunden som andra inställningar, listorna behålls och frågan besvaras direkt. Samma långsamma fråga gjorde också att Data-vyn hackade när den ritades om medan man bara tittade. Nya rader i tidsloggen visar tiden. | Klar 2026-09-29 (första offentliga versionen) |
| F46 | Kalendern | Efter att ett möte ändrats eller tagits bort tog det cirka 0,2 s två gånger (när mötet sparades och när kalendern läste mötena igen). Hittat: mötena sorterades genom att datumen tolkades om i varje jämförelse, ungefär 40 000 gånger. Nu tolkas varje datum en gång, och oförändrade möten återanvänds i stället för att göras om. Ordningen är exakt densamma. | Klar 2026-09-29 (första offentliga versionen) |

### Organisationsnamn, rättelser och lönekällor

| Nr | Område | Ändring | Status |
|---|---|---|---|
| – | Organisationsträd | En stavning: en affiliering, anställning eller utbildning som är kopplad till en organisation visar organisationens namn, och en som är kopplad till en enhet visar enhetens namn som avdelning (engelska: namnet i publikationsadressen). Texten skrivs om när appen startar (säkerhetskopia först), när en organisation eller enhet byter namn och när man väljer enhet på en affiliering. Rader utan koppling ändras inte. | Klar 2026-09-29 (första offentliga versionen) |
| – | Granskningsuppdrag, lön, forskarkortet | Appens särregel för en enskild granskning är borttagen (en engångsrättning av den granskningen togs senare också bort, se Omgång 8). Varje lönekälla har nu en färg som väljs i lönekällans ruta; dagens färger och de svenska/engelska namnen för Tjänstledighet och lärosätet sparas en gång på lönekällorna, så inget ser annorlunda ut. De oanvända rutorna för anställningar och utbildningar på forskarkortet är borttagna (de redigeras under CV). | Klar 2026-09-29 (första offentliga versionen) |

### Ansökningar, undervisning och exporter

- Det som tidigare var fast inbyggt går nu att ändra under Inställningar, och allt börjar med samma värden som förut: nya ansökningar (öppnar om 1 månad, sista dag om 3 månader, valuta, status), vilka valutor som går att välja, gränserna för små/mellanstora/stora belopp, standardprogrammet för undervisning, orden som gör en kurs till klinisk undervisning ("region"), ordet för termin och dess översättning (Termin/Semester), Wordmallen, fakulteten och handledningsreglerna i exporten av pedagogiska meriter samt texterna om finansiering och etik. Hjärt-Lungfondens lista har ett val för antal år, och författarlistor har valet "Visa alltid mitt namn". Beräkningen av lektorat, docentur och professur är borttagen (beslut); den visades inte någonstans.
- Tidskriftsmått (JIF, kvartil, norska listan) hämtas från publikationsåret, och finns inget värde för det året används det senaste registrerade året. Appen skriver inte längre om tidskrifternas år till 2025 när den startar. I CV- och publikationsexporten finns valet "Tidskriftsmått från: Publikationsåret / Senaste registrerade året".

### Hemorganisation, påminnelser och kalenderkategorier

- Namn som tidigare var inbyggda i appen är nu inställningar: under Inställningar > Hemorganisation väljs hemland (Sverige), hemregion och huvudarbetsgivare. På en organisation finns rutan "Använd som lönekalkyl för ansökningar", och semesterdagar och semestertillägg går att ändra i lönekalkylen. Appen lägger inte längre till eller tar bort roller på organisationer utifrån namnet – de roller du kryssar i gäller.
- Under Inställningar > Kalender väljs när påminnelser om anslag och uppgifter skickas och när en uppgift blir gul. Varje kalenderkategori har rutorna "Räkna inte i mötesstatistik", "Klinisk tid" och "Ledighet" (i stället för att appen letar efter namnen Klinik, Resa och Semester). Allt är inställt så att appen fungerar som förut tills du ändrar något.

### Organisationsträdets verktyg borttaget

| Nr | Område | Ändring | Status |
|---|---|---|---|
| F21 | Organisationsträd | Verktyget som byggde organisationsträdet är borttaget helt (beslut), eftersom trädet redan finns i datan. Med det försvann alla inbyggda listor över kända organisationer, sjukhus, kliniker, vårdcentraler och stavningar, och filen med vetenskapliga adresser (vetenskapliga_adresser.json) som bara verktyget läste. Inga organisationer, enheter eller kopplingar hos forskarna ändras. Enheterna redigeras som förut på organisationens sida, och publikationsadressen, rättelsen av gamla id:n och de officiella namnen fungerar som tidigare. | Klar 2026-09-29 (första offentliga versionen) |

### Handledningstimmar

- På varje doktorand finns rutan "Handledningstimmar (undervisningsmerit)" där du själv skriver in dina timmar. Bredvid visas i grått ett förslag räknat från fakultetens regler och dina handledardatum (huvudhandledare 40 h per 6 månader, högst 320 h; bihandledare enligt inställningarna), och knappen "Använd förslaget" fyller i det. Vid första starten fylls förslaget i en gång för doktorander där rutan är tom (ditt beslut); sedan ändrar du själv.
- Exporten av pedagogiska meriter använder bara timmar du skrivit in; saknas de blir rutan tom (tidigare lades timmarna per termin ihop). I förhandsvisningen står "ej angivet" där timmar saknas. Rubrikerna med reglerna finns kvar.

### Handledningstimmar från perioderna och klinisk undervisning som kryssruta

- Ersätter "Handledningstimmar" ovan (ditt beslut): rutan "Handledningstimmar (undervisningsmerit)", förslaget och knappen "Använd förslaget" är borttagna. Timmarna i listan "Din handledarinsats per tidsperiod" är timmar per termin och räknas ihop fram till idag eller periodens slutdatum (6 månader = 1 termin, räknat i proportion). Varje rad visar "Summa hittills" och under listan står "Totalt hittills: N h (till idag)". Exporten av pedagogiska meriter använder den summan; "ej angivet" finns inte längre och rutan är tom bara om inga timmar per termin är ifyllda. Timmar som redan fyllts i på din Mac används inte och försvinner när doktoranden sparas nästa gång.
- Klinisk undervisning är en kryssruta på kursen i stället för ordet "region" i organisationens namn. Vid första starten kryssas rutan en gång i för de kurser som ordet placerade under Klinisk undervisning, så ingen kurs flyttar. Inställningen "Ord som betyder klinisk undervisning" är borttagen.

### Doktorandvyns tidslinje

- Tidslinjen överst på doktorandsidan har samma bakgrund och samma textstorlek som resten av sidan. Etiketter på milstolpar som skulle krocka läggs växelvis under och över raden, delarbeten som ligger på samma ställe staplas, och aktiviteter som ligger nära varandra blir en ring med antal (klicka för att se listan). Tidigare aktiviteter visas nu också (ifyllda = genomförda, ofyllda = planerade), och status står i ord: Preliminärt, Bokat, Genomfört, Beräknat.
- Fel rättat: "Genomfört" gick inte att välja för planeringsseminarium (och antagning) eftersom det inte fanns någon plats att spara det på. Nu sparas det. Gamla data ändras inte; en milstolpe visas som klar (grön bock) först när den är markerad Genomfört.

### Alla kopplingar via id

- Överallt där en post hör ihop med en annan (anslagsgivare, medelsförvaltare och projekt på ansökningar, projekt och tidskrift på publikationer, projekt och tidskrift på konferensbidrag, tidskrift och organisation på granskningsuppdrag, lärosäte på kurser, moment och doktorander, forskarnas rader på organisationens sida, listor, räkningar, statistik, exporter och Data-vyn) avgör nu den fasta kopplingen, och det skrivna namnet används bara för äldre rader som saknar koppling. Byter en organisation, ett projekt, en tidskrift eller en forskare namn hittas allt som hör dit ändå, och ett gammalt namn blir aldrig en egen organisation eller ett eget projekt.
- Granskningsuppdrag får en fast koppling till organisationen. Befintliga uppdrag kopplas en gång vid start när exakt en organisation har namnet; den skrivna texten står kvar. När en organisation tas bort tappar forskarnas rader, granskningsuppdrag och doktorander som pekar på den kopplingen, men deras text finns kvar.

### Inställningar förklarar sin effekt

- Varje inställning har nu en grå rad "Påverkar: …" som säger vad den ändrar i appen (vilka vyer, exporter och beräkningar). Där en inställning i dag inte gör något står det också (påminnelserna om ansökningar är avstängda i appen och beloppsgrupperna visas ingenstans). Valet "Huvudarbetsgivare" under Hemorganisation är borttaget eftersom det inte påverkade något (ditt beslut); ett sparat värde ligger kvar orört i datan.
- Alla par av svenska och engelska texter i Inställningar (undervisningsbegrepp, program och termin, texterna om finansiering och etik, översättningar och mediaspråk) visas i två kolumner, Svenska till vänster och Engelska till höger, en tät rad per begrepp utan ruta runt varje rad. Långa texter växer nedåt i stället för att rulla inuti fältet.

### Snabbare, omgång 2

- Kalenderns 1 800 aktiviteter gjordes om helt (cirka 0,16 s) efter varje ändring av en organisation, eftersom kliniktiden hämtar hemregionen därifrån. Nu görs de bara om när hemregionen, hemlandet eller inställningen "Klinisk tid" faktiskt ändras. Att klicka sig igenom en arbetsgivare i Organisationer sparade dessutom hela organisationslistan varje gång, fast inget var ändrat (lönekalkylens perioder fick nya interna nummer vid varje visning); det gör den inte längre.
- Organisationens sida räknar inte längre om vilka forskare som hör till lärosätet vid varje omritning, doktorandens sida går inte igenom alla kalenderaktiviteter för varje handledningsperiod, och kontrollen efter varje sparning (och Data-vyn) gör inte om de 3 000 tidskrifternas kontroll när något annat än en tidskrift ändrats. Nya rader i tidsloggen visar tiderna.
### Påminnelser om ansökningar och beloppsgrupper

- Påminnelser om ansökningar är påslagna (ditt beslut). Under Inställningar > Kalender > Påminnelsetider finns rutan "Påminnelser om ansökningar" (ikryssad från början). Notiserna skickas när notiser är påslagna under Uppgiftsnotiser, och macOS frågar om lov bara en gång. Bara ansökningar som ska sökas, väntar på beslut eller är beviljade får påminnelser – avslagna, tillbakadragna och ej sökta får inga. Påminnelser som redan är försenade skickas direkt bara om de var aktuella den senaste veckan, så gamla ansökningar skickar inte en hög notiser första gången.
- Statistik > Anslag har en ny tabell "Beloppsgrupper": per grupp (under 250 000 kr, 250 000–1 miljon, över 1 miljon, eller dina gränser) antal ansökningar, hur många som beviljades och beviljad summa i miljoner kronor. Tabellen följer valet egna/alla ansökningar.

### Aktiviteter och uppgifter kopplas likadant

- Aktiviteter och uppgifter i kalendern har nu samma kopplingsrader: Projekt, Organisation, Undervisning, Doktorand, Anslag och Publikation, med flera val per rad och en röd knapp "Ta bort" i text. Under "Undervisning" står varje kurs med sina undervisningsuppdrag indragna under sig, så du kan koppla till hela kursen eller till ett uppdrag. Uppgiftens deltagare kopplas till forskarna precis som aktivitetens. Kurssidan har fått en egen uppgiftslista, och doktorand-, uppdrags- och kurssidorna visar "Kopplade aktiviteter och uppgifter". Kalenderns detaljruta visar också kopplad doktorand och kurs, och påminnelser räknas för kurser och doktorander.
- Doktorandens tidslinje visar bara aktiviteter och uppgifter som är kopplade till doktoranden, inte längre sådant som bara hör till doktorandens projekt eller har namnet bland deltagarna. De aktiviteterna föreslås i stället under Datakvalitet, "Aktiviteter att koppla till doktorand", där du väljer "Koppla" (går att ångra) eller "Dölj". Inget kopplas automatiskt och inga befintliga uppgifter skrivs om.

## Omgång 6 – klar 2026-09-29 (första offentliga versionen)

| Nr | Område | Ändring | Status |
|---|---|---|---|
| F13d | Kopplingar | Fler ställen avgör "är det här jag?" eller "är det här den forskaren?" med den fasta kopplingen först och namnet bara när kopplingen saknas: årsrapporten (mina ansökningar, huvudsökande, mina publikationer), CV-förhandsvisningen, statistiken (huvudsökande, första/sista författare), publikationslistan, kalenderns forskarfilter, händelserna som visas på forskarkortet och mötesstatistiken per forskare. En post som skrevs med ett gammalt namn räknas därför fortfarande rätt efter ett namnbyte. Namnen visas som de är skrivna. | Klar 2026-09-29 (första offentliga versionen) |
| F43 | Data-vyn | Ny kontroll: en post som är kopplad till en forskare som inte längre finns (medsökande, projektmedarbetare, författare, korresponderande författare, deltagare i uppgifter och möten) visas som "Kopplad till en forskare som inte finns", med namnet som står i posten. Kontrollen körs också efter varje sparning, så en sparning som lämnar en sådan koppling ger en påminnelse; där ingår även bidragsförfattare, presentatör, kongressdeltagare, doktorand och handledare. De befintliga raderna för doktorand, handledare, student, presentatör, bidragsförfattare och kongressdeltagare finns kvar som förut, så ingenting visas två gånger och dolda varningar förblir dolda. | Klar 2026-09-29 (första offentliga versionen) |
| F44 | Kalendern | Kalendern var trög i 2–3 sekunder efter varje ändring. Hittat: en ändring räknade om kalendern två gånger, den första gången helt från början. Nu räknas den om en gång och bara för den ändrade händelsen (gäller även borttagning). Efter varje sparning läste appen dessutom arkiverade poster från databasen inför en säkerhetskopia som ändå inte skulle göras (det görs högst en var 15:e minut); det hoppas nu över när appen vet att en färsk kopia finns. Nya rader i tidsloggen visar hur lång tid varje steg tar. | Klar 2026-09-29 (första offentliga versionen) |
| F21 | Organisationsträd | En organisation kan ha enheter i hur många nivåer som helst (fakultet, institution, centrum, klinik, avdelning), var och en med giltighetstid. Varje enhet vet om den skrivs i en vetenskaplig adress och vad den heter på engelska där; för vissa institutioner skrivs institutionen även när man hör till en avdelning, och fakulteter och centrum skrivs aldrig. Forskarnas affilieringar, anställningar och utbildningar pekar på organisation och enhet, och texten finns kvar som visning. Appen kan skriva forskarens adressrader (universitetet före regionen, en rad per enhet). En assistent föreslår trädet utifrån listan över vetenskapliga adresser och det som redan står hos forskarna: olika stavningar slås ihop (till exempel en förkortning, institutionens fulla namn och den engelska formen), en sjukhusklinik blir en klinik under sin region, vårdcentralerna hamnar under Primärvårdscentrum, organisationer som bara finns som text föreslås som nya, och universitetssjukhus blir enheter under sin region. En anställning där bara ett sjukhusnamn står får den texten borttagen (beslut). Inget ändras förrän förslaget godkänts, och godkännandet går att ångra. Skärmarna: assistenten öppnas med knappen "Bygg organisationsträd…" i Data-vyn (sektionen Organisationsträd) och överst i listan under Organisationer. Rutan visar en sammanfattning, sådant som är bra att veta, nya organisationer, nya enheter per organisation med hela sökvägen och skälet, och varje rad hos forskarna som kopplas (namn, sorts rad, vad som står nu, vart den pekar och varför, och en tydlig rad när en avdelningstext tas bort); inget sparas förrän man trycker "Godkänn och spara". Saknas adresslistan förklaras det, och med "Välj adresslista…" kopieras filen in i Reference-mappen och förslaget räknas om. På en organisations sida finns sektionen "Enheter" med trädet indraget under sina överenheter: svenskt och engelskt namn, förkortning, engelskt namn i adress, ort, giltig från och till (ett slut före start markeras), "Ingår i publikationsadress" och "Avdelningar under ingår inte i adressen", knappen "Lägg till enhet" och för varje enhet en rullgardin "Välj…" med Lägg till underenhet, Flytta till… och Ta bort… (bara när ingen rad hos forskarna använder enheten; annars står hur många rader som gör det). Bland organisationens uppgifter finns också "Engelskt namn i publikationsadress" och "Ordning i publikationsadress" (ingen, 1, 2 eller 3). På forskarens affilieringar och på anställningar och utbildningar (under CV) finns en rullgardin "Enhet: …" med organisationens enheter som gäller i dag; valet fyller i avdelningstexten, och byts organisationen tas en enhet som inte hör dit bort. Under affilieringarna visar rutan "Publikationsadress" forskarens adressrader numrerade, med "Kopiera" för varje rad och "Kopiera alla".  Universitetssjukhus i andra regioner skrivs i publikationsadressen med sjukhusets namn i stället för regionens, så som forskarna där själva skriver på PubMed. | Klar 2026-09-29 (första offentliga versionen) |
| F21 | Organisationsträd | Sektionen "Enheter" på en organisations sida är omgjord till två kolumner. Till vänster en kort lista med en rad per enhet, indragen under sin överenhet och med namnet på appens språk; alla grenar är stängda från början och öppnas med pilen, mallar har "(mall)" efter namnet och en liten grå siffra visar hur många rader hos forskarna som använder enheten. Överst finns rutan "Sök enhet" (visar träffarna med enheterna ovanför) och knappen "Lägg till enhet". Till höger visas den valda enheten: svenskt namn, ett enda engelskt namn (som också används i publikationsadressen), ort, "Med i publikationsadressen", "Avdelningar under ingår inte i adressen" (bara när enheten har underenheter), den nya rutan "Skrivs i stället för organisationen i adressen" (till exempel ett universitetssjukhus i stället för regionen), "Så blir adressen:" med den färdiga adressraden och "Kopiera", hur många rader hos forskarna som använder enheten, samt "Lägg till underenhet", "Flytta till…" och "Ta bort enheten". Förkortning och giltighetsdatum visas inte längre (uppgifterna finns kvar), och valet "Visa även enheter som har upphört" är borta: alla enheter visas. En enhet går nu att ta bort även när den används eller har underenheter; rutan som frågar först berättar hur många underenheter och rader det gäller och låter en välja "Ta bort med underenheter" eller "Ta bort bara den här, flytta underenheterna upp en nivå". Rader hos forskarna som pekade på en borttagen enhet behåller organisationen men förlorar enheten. Borttagningen går att ångra. | Klar 2026-09-29 (första offentliga versionen) |
| F21 | Organisationsträd | Nya organisationer från trädassistenten får samma sorts id som alla andra poster, och de 26 som redan skapats får ett nytt id en gång vid nästa start (allt som pekar på dem följer med), så varningen om äldre id:n i Data-vyn försvinner. Knappen "Bygg organisationsträd…" och sektionen Organisationsträd i Data-vyn är borttagna eftersom trädet redan är byggt. | Klar 2026-09-29 (första offentliga versionen) |
| F21 | Organisationsträd | Trädassistenten, knappen "Välj adresslista…" och adresslistan i Reference-mappen togs senare bort när trädet var byggt (se Omgång 7, "Organisationsträdets verktyg borttaget"). | Klar 2026-09-29 (första offentliga versionen) |

## Kommande

| Nr | Område | Ändring | Status |
|---|---|---|---|
| F39 | Förråd | Privat dataförråd `footprint-data` med kopia av Application Support; koden i ett publikt förråd med ny historik. Ersätter F20. | Klar 2026-09-29 |
| F40 | Inställningar | Reglerna för hemregionen och lärosätet blir inställningar. Hemland och hemregion väljs under Inställningar > Hemorganisation, lönekalkylens organisation med rutan "Använd som lönekalkyl för ansökningar", och klinisk undervisning är en kryssruta på kursen (omgång 7, F47). Sista resten borttagen: en organisation som appen själv skapar utifrån en ansökan får bara den roll ansökan ger den (Anslagsgivare eller Medelsförvaltare). Rollerna Arbetsgivare och Lärosäte gissas inte längre utifrån namnet ("universitet", "högskola" och liknande) utan kryssas i för hand (beslut 2026-09-29). Befintliga organisationer ändras inte. | Klar 2026-09-29 |
| F48 | Forskare | Affilieringar: när en enhet är vald visas inte fritextfältet för avdelning (enhetens namn står i "Enhet: …" och sparas som avdelning som förut). När man väljer enhet, eller byter till en annan organisation, fylls ort och land i: orten från enheten, annars närmaste överenhet med ort, annars organisationen; landet från organisationen. Finns ingen uppgift står det som redan var ifyllt kvar. Fälten går att ändra för hand efteråt. Befintliga affilieringar ändras inte förrän man väljer på nytt. | Klar 2026-09-29 |
