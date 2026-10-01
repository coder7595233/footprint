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

## Omgång 16 – pågår (filter, färger, typsnitt och ord)

| Nr | Område | Ändring | Status |
|---|---|---|---|
| F108 | Filter, alla listor | Filter sparas mellan omstarter (beslut 2026-10-01), men en filtrerad lista visar alltid raden "Filtrerad lista: x av y visas" med aktiva filter, "Sparat från förra gången" när filtret kom tillbaka vid start, och "Rensa filter". Tomma listor säger "Inga poster matchar filtren". Valet "behåll filter = av" gäller nu också vid start. | Pågår |
| F109 | Ansökningar, Kongresser, Undervisning, Doktorander | Årsfiltret täcker som standard alla år och växer med nya år; ett eget val sparas. Det krympte förut till innevarande år vid varje omstart, och nya poster i nya år försvann. | Pågår |
| F110 | Arkiv | "Ta bort valda" tar bara bort poster som syns; valet rensas när sökningen eller kategorin ändras. | Pågår |
| F111 | Navigering, nya poster | När du går till en post som ett filter döljer, eller skapar en ny, rensas bara de filter som döljer den. Valet hoppar inte bort från det du redigerar. | Pågår |
| F112 | Filter, detaljer | Projektfiltret i Ansökningar sparas per projekt och tål namnbyten; Forskares filter "ofullständiga uppgifter" syns; Granskningsuppdrag har knappar för status (Pågående, Försenade, Klara, Avböjda, Utan status) och kategori (beslut 2026-10-01); Publikationer har "Refuserad"; Doktorander använder faktiskt disputationsdatum; Kalendern visar kongresser när Konferenser-kolumnen är dold och "Visa i kalendern" fungerar med filter; Undervisningens programfilter tål språkbyte; Datavyn visar inte "Inga problem" när ett filter döljer dem; sökningen fungerar lika överallt. | Pågår |
| F113 | Färger | En gemensam färgkälla (beslut 2026-10-01): grönt = klart med positivt resultat, gult = pågår eller väntar, orange = kräver åtgärd snart, rött = negativt eller passerad frist, grått = inget att göra nu, vitt = ingen status än, blekare text = ansökan som inte öppnat. Blått är inte längre en statusfärg. Projekt: grönt när pågående med datainsamling, etiknummer eller beviljade medel; gult när pågående utan dem eller planerat med något av dem; vitt planerat; grått avslutat. Statistiken följer färgvalen och mörkt läge. Läsbar text på alla färgfält, dagens-markering och låssymbol samordnade. | Pågår |
| F114 | Projekt | När ett planerat projekt får beviljade medel, en påbörjad datainsamling eller ett etiktillstånd (sökt eller beviljat) frågar appen om projektet ska ändras till Pågående (beslut 2026-10-01). "Inte nu" kommer ihåg just den händelsen. | Pågår |
| F115 | Typsnitt, ord, belopp | Typsnitten följer Inställningar överallt (beslut 2026-10-01). Samma ord för utfall överallt (Beviljat/Granted, Avslag/Declined, Väntar svar/Awaiting decision, Refuserad/Rejected för publikationer). Belopp skrivs kr/mkr på svenska och SEK/MSEK på engelska. ÅÅÅÅ-MM-DD i svenska fält. | Pågår |
| F116 | Ta bort | Borttagning frågar alltid först, i alla vyer (beslut 2026-10-01), men bara en gång även när posten har kopplingar. | Pågår |

## Omgång 15 – klar 2026-10-01 (#10)

| Nr | Område | Ändring | Status |
|---|---|---|---|
| F101 | Export, säkerhet | I bilagelistan (bilagor.csv) visas ett fält som börjar med =, +, - eller @ som text i Excel och körs inte som formel. | Klar |
| F102 | E-post, säkerhet | E-postlänkar till kontakter och forskare kräver en vanlig adress. Text som "namn@x.se?bcc=..." gav dolda mottagare eller ifylld text i utkastet. | Klar |
| F103 | Påminnelser | Anslagspåminnelser kommer på inställd tid även de dagar sommartid börjar eller slutar (de kom en timme fel). "Disponeringstiden har passerat" kommer dagen efter sista dispositionsdagen. Kalenderns påminnelselista sparas innan påminnelserna läggs till, så att två snabba uppdateringar inte lämnar kvar påminnelser för borttagna uppgifter. | Klar |
| F104 | Växelkurser | Kurser från tio dagar före det första datumet sparas, så att kurshistoriken inte laddas ner vid varje sparning när det datumet är en helgdag. Bara ett normalt svar från ECB läses in. | Klar |
| F105 | Projekt | Utfallskortet räknar inte "Ej sökt" i totalen, så att andelarna går ihop. | Klar |
| F106 | Felmeddelanden | En lyckad automatisk sparning tar bara bort sitt eget felmeddelande, inte till exempel ett om en misslyckad säkerhetskopia. | Klar |
| F107 | Stabilitet | Ett mycket långt tal (till exempel ett inklistrat kontonummer) räknas inte som belopp och kan inte få appen att krascha. Fönstren som gör PDF av CV och export kör inga skript och öppnar inga andra sidor. Vid Ångra och vid återställning från arkivet sparas arkivet först, så att skärm och databas inte kan visa olika saker om arkivet inte går att spara. | Klar |

## Omgång 14 – klar 2026-10-01 (#9)

| Nr | Område | Ändring | Status |
|---|---|---|---|
| F92 | Bilagor, säkerhet | En sökväg till en bilaga som kommer från databasen (till exempel en importerad) kan inte längre peka utanför appens lagringsmapp, utom till en PDF-fil. Bara riktiga PDF-filer kopieras in i appen och öppnas; en app, ett skript eller en webbsida öppnas aldrig. Tillfälliga kopior av PDF:er får ett säkert filnamn. | Klar |
| F93 | Projektuppgifter, kongresser | Uppgiften "Nya medel" läggs inte tillbaka vid varje start eller Ångra när du har tagit bort den. Du läggs inte tillbaka som deltagare på en kongress du tagit bort dig från, när appen startar eller när du sparar samma resa eller boende igen. | Klar |
| F94 | Data, översättningar | Låsta projekt och medieframträdanden visas inte i listan med översättningar att rätta och kan inte ändras därifrån. | Klar |
| F95 | Redigerare | Text du just skrivit försvinner inte när samma post ändras någon annanstans (projekt, publikationer, media, granskningar). En halvifylld ny affiliering hos en forskare töms inte. Etikansökningar, clinicaltrials-registreringar och datainsamlingar följer sin rad, så att det du skriver inte hamnar på raden under. Kurs- och undervisningsredigerarna fastnar inte som "osparade". | Klar |
| F96 | Publikationer | Att bara klicka på en publikation ändrar inte längre dess korresponderande författare eller CRediT-roller. | Klar |
| F97 | Kalender, inställningar | En kalender- eller inställningsändring som väntar på att sparas försvinner inte om en annan sparning misslyckas. | Klar |
| F98 | Statistik | Beloppsgrupperna använder beloppet i kronor (ett anslag på 200 000 euro hamnade i gruppen under 250 000). Undervisningstimmar räknar terminen då perioden slutar, och en period utan slutdatum som inte börjat än räknas inte. | Klar |
| F99 | Ansökningar | En gammal post sparad som Beviljat, Avslag eller Tillbakadragen utan beslutsdatum blev "Väntar svar" och förlorade beviljat belopp vid nästa sparning. Nu behåller den sitt utfall; beslutsdatum blir förväntat beslutsdatum, ansökningsdatum eller stängningsdag, markerat som osäkert. | Klar |
| F100 | Inställningar, export | Kopian av all data till en mapp (förut Google Drive) är avstängd från början (beslut 2026-10-01). I Inställningar > Data och backuper slår du på den och väljer en valfri mapp, till exempel i Google Drive eller OneDrive. | Klar |

## Omgång 13 – klar 2026-10-01 (#8)

| Nr | Område | Ändring | Status |
|---|---|---|---|
| F82 | Projekt | När man byter från ett projekt till ett annat medan en ändring väntar på att sparas, skrivs inte längre det nya projektets anteckning, webbadress och medarbetare in i det gamla. | Klar |
| F83 | Ångra | Ångra fungerar också direkt efter en automatisk sparning (appen kunde tro att den gamla versionen redan var sparad och tappa ångra-steget). | Klar |
| F84 | Inställningar och dolda varningar | Ändringar i inställningar som ännu inte hunnit sparas följer med när man slår ihop dubbletter eller gör andra ändringar, i stället för att skrivas över. | Klar |
| F85 | Ansökningar, organisationer | Om samma post ändras någon annanstans (ångra, sammanslagning, namnbyte) medan den är öppen, visas det nya. Förut kunde nästa automatiska sparning skriva tillbaka de gamla värdena. Det du själv skrivit men inte sparat skrivs aldrig över. | Klar |
| F86 | Stabilitet | Två tidskrifter (eller andra poster) med samma namn eller id kan inte längre få appen att krascha; den första används. | Klar |
| F87 | Valuta | Belopp i utländsk valuta utan växelkurs räknas som 0 i summorna och står separat som "ej omräknat" (beslut 2026-09-30). Förut räknades de som kronor. Gäller projektets och organisationens summor, årsrapporten, projektexporten och doktorandens anslag, som nu också räknas om till kronor. | Klar |
| F88 | Valuta | Lönekalkylens belopp (alltid i kronor) används inte längre som budget för en ansökan i annan valuta, där det räknades om som om det vore euro eller dollar. | Klar |
| F89 | Belopp | Inklistrade belopp som "1,5 M", "1,5 milj", "2 mkr", "250 tkr", "40,000 EUR" och "1.250.000" tolkas rätt (förut blev "1,5 M" 1 kr och "40,000 EUR" kunde bli fel). | Klar |
| F90 | Data | Knappen "Visa alla dolda" i Data-vyn visar alla dolda varningar igen på en gång, även de som dolts i äldre versioner. Den frågar först och kan ångras. Reglaget "Dolda" visar antalet, och varje dold rad har knappen "Visa igen". | Klar |
| F91 | Ansökningar, kalender | En utlysning som har stängt men fortfarande står som "Att söka" försvann med filtret "Hitta nya/Framtida anslag" och ur anslagsflödet. Nu ligger den kvar: i listan står "Svara" i kolumnen Stänger, i anslagsflödet "Stängd – sökt?". I kalendern ligger "Sökt eller inte sökt?" på dagens datum varje dag tills du svarat; klick ger frågan med knapparna Sökt, Ej sökt, Öppna ansökan och Senare. Sökt sätter ansökningsdatum till stängningsdagen (markerat osäkert), Ej sökt sätter Ej sökt-datum till stängningsdagen. Dagen efter stängning kommer också en notis som öppnar samma fråga. Kan ångras. | Klar |

## Omgång 12 – klar 2026-09-30 (#7)

| Nr | Område | Ändring | Status |
|---|---|---|---|
| F71 | Årsrapport | Som standard tas bara anslag med där du är huvudsökande (beslut 2026-09-30). Valet "Anslag: Mina / Mina + medsökande" tar med medsökandeanslagen; då visas kolumnen och tabellen för medsökande som förut. CV:t hade redan samma val. Alla artiklar tas med som förut. | Klar |
| F72 | CV, årsrapport | Konferensbidrag tas med bara när de är inskickade (inskickningsdatum, inget beslut än) eller accepterade/presenterade (beslut 2026-09-30). Planerade och avslagna tas inte med. | Klar |
| F73 | CV | Publicerade research letters står med bland originalartiklarna (de föll bort ur det egna CV:t). Granskningsuppdrag står i datumordning, nyast först. Anslagens belopp står i anslagets egen valuta (alla belopp stod som SEK). | Klar |
| F74 | Publikationslistor (AMA) | Accepterade artiklar kommer med i listan, under "Artiklar accepterade eller under granskning" (de föll bort). Status, "citeringar" och "Norska listan" skrivs på exportens språk (de stod på engelska även i svenska exporter). | Klar |
| F75 | Impact factor | Ett värde för publiceringsåret går före det senaste årets värde, även när det finns i en annan rad eller lista för tidskriften. | Klar |
| F76 | Statistikexport (Excel) | Anslagsarket räknar dina anslag som huvudsökande, inte alla anslag i appen. Publikationsarket räknar dina publikationer och alla citeringar under året till dem (förut bara citeringar till artiklar från samma år). | Klar |
| F77 | Doktorander, handledning | Handledningstimmar räknas på ett sätt överallt (beslut 2026-09-30): i proportion till dagarna per termin, där en hel vårtermin (jan–jun) eller hösttermin (jul–dec) ger hela terminens timmar. Gäller "Summa hittills", tidslinjen, doktorandstatistiken, statistiken och årsrapporten (förut räknades en hel termin för varje termin perioden berörde). En kort period över sommaren räknas nu i båda terminerna. | Klar |
| F78 | Doktorander, Retendo | Handledning som inte är bekräftad i Retendo markeras alltid röd (beslut 2026-09-30), också pågående och kommande terminer: på tidslinjen, med en röd kant på perioden och i doktorandlistan. En period utan timmar syns också. | Klar |
| F79 | Påminnelser | En påminnelse om ett anslag skickas en gång (den kom två gånger när appen uppdaterades efter att den visats) och försvinner inte vid två snabba uppdateringar. | Klar |
| F80 | Projektuppgifter | Uppgifter som väntar på "Publikation tillagd", "Publikation publicerad" eller "Medlen tar slut" får dagens datum när det händer (de startade aldrig). Projektuppgifter som följer ett beviljat anslag sparas nu också när anslaget sparas med knappen. | Klar |
| F81 | Data | En varning om saknade uppgifter som döljs från och med nu visas igen om ett nytt fält saknas på samma post. Varningar som redan är dolda förblir dolda. | Klar |

## Omgång 11 – klar 2026-09-30 (#6)

| Nr | Område | Ändring | Status |
|---|---|---|---|
| F60 | Organisationer, OH | Lönekalkylen visas bara för organisationer markerade som arbetsgivare. Kalkyler som låg sparade hos andra organisationer syntes inte men gav ändå OH-förslag (en förvaltare fick OH från en annan organisations kalkyl). Nu hämtas OH-förslag bara från en arbetsgivares kalkyl. Engångsändring vid första start (beslut 2026-09-30): dolda kalkyler hos organisationer som inte är arbetsgivare tas bort; arbetsgivarnas kalkyler och den kalkyl som valts under Inställningar ändras inte. | Klar 2026-09-30 (#6) |
| F61 | Utlysningar och anslag | En post med status "Ej sökt" döljer ansökningsdelen men behåller det som står där. Posten visar nu en rad som räknar upp vilka fält som har innehåll ("Dolda uppgifter från ansökningsdelen: …") och att de visas igen om statusen ändras. | Klar 2026-09-30 (#6) |
| F62 | Doktorander | Doktorander tas aldrig bort automatiskt (tidigare försvann doktorander som skapats från undervisningsrader utan egna uppgifter, vid start och när doktorandsidan öppnades). | Klar 2026-09-30 (#6) |
| F63 | Alla listor | Delete-tangenten tar inte längre bort posten direkt. Den frågar först och gör ingenting på en låst post (då visas ett meddelande). Gäller utlysningar, publikationer, projekt, organisationer, forskare och tidskrifter. | Klar 2026-09-30 (#6) |
| F64 | Borttagning och ångra | När en publikation, ett konferensbidrag, ett medieframträdande eller ett sakkunniguppdrag tas bort ligger PDF:en kvar, så att Ångra och arkivet får tillbaka posten med sin fil. Ångra efter en borttagning tar också bort posten ur arkivet (den låg förut kvar där och kunde återställas en gång till). | Klar 2026-09-30 (#6) |
| F65 | Organisationer | När en organisation tas bort står dess namn kvar som text i utlysningar (finansiär och förvaltare), kurser och moment; bara kopplingen försvinner. Tidigare blev fälten tomma. | Klar 2026-09-30 (#6) |
| F66 | Undervisning | Kurskodshistoriken läggs bara till på kurser som saknar egen historik. En lista som ändrats för hand skrivs inte längre över vid varje start. | Klar 2026-09-30 (#6) |
| F67 | Organisationer | Två inbyggda engelska namn för organisationer är borttagna ur koden (de skrev över det engelska namnet vid varje uppdatering). Namnen som redan står i datan ändras inte. | Klar 2026-09-30 (#6) |
| F68 | Kopplingar | En post utan fast koppling kopplas via namnet bara när exakt en organisation, förvaltare eller ett projekt har det namnet. Har två samma namn förblir posten okopplad och behåller sin text. | Klar 2026-09-30 (#6) |
| F69 | Dubbletter | Sammanslagning av organisationer tar med dubblettens kongresser och kontaktpersoner, och resor, boenden, uppgifter, finansiärers "Prioriterad förvaltare" och OH-undantag pekar om till organisationen som behålls. Konferensbidrag tappar inte längre sin kongress. Sammanslagning av projekt och publikationer pekar om uppgifternas kopplingar. Sammanslagning av forskare pekar om studenter, konferensbidrag, kongressdeltagare och vem som är du i appen. Innan en sammanslagning ändrar låsta poster listas de, och inget händer utan "Slå ihop ändå". Borttagning av en namnvariant listar nu även låsta utlysningar och handledare. | Klar 2026-09-30 (#6) |
| F70 | Bygge | Byggvarningen i doktorandtidslinjen är åtgärdad. | Klar 2026-09-30 (#6) |

## Omgång 10 – klar 2026-09-30 (#5)

| Nr | Område | Ändring | Status |
|---|---|---|---|
| F53 | Doktorander | Tidslinjen överst på doktorandsidan: de tre ringarna till höger är borttagna (Anslag står kvar under tidslinjen, bredvid en rad som förklarar markeringarna). Fem år syns åt gången och resten nås genom att rulla i sidled; vyn öppnas centrerad på i dag och knappen "Idag" rullar tillbaka. Tunna linjer visar årsgränserna. Delarbeten får en linje från den dag arbetet påbörjades (tidigaste datum i statushistoriken, arbetsstatus eller inskickning) fram till markeringen; heldragen när arbetet är publicerat, streckad annars, och ett publicerat arbete står på sitt publiceringsdatum. Kurser: heldragen del = genomförda poäng, streckad del = ej genomförda. Handledning visas per termin: heldragen = bekräftad i Retendo, streckad = ej bekräftad, och en röd kant till vänster när terminen är slut men inte bekräftad. Tidslinjen har lite luft i båda ändar, så en milstolpe på axelns första eller sista dag (till exempel disputation 31 december) inte skärs av. | Klar 2026-09-30 (#5) |
| F54 | Forskare | Affilieringar: "Enhet: " står inte längre framför enhetens namn. Organisation, ort och land är cirka 30 % smalare så att enhetens namn får plats, och "Ta bort" är en papperskorg så att e-postfältet får mer plats. | Klar 2026-09-30 (#5) |
| F55 | Organisationer | Rubriken "Enheter" har samma storlek som till exempel "Kontaktpersoner", och den långa hjälptexten under rubriken är borttagen. | Klar 2026-09-30 (#5) |
| F56 | Utlysningar och anslag | "Ansökningar" heter nu "Utlysningar och anslag" i menyn och listan, och knappen heter "Ny utlysning". I posten heter avsnitten "Utlysning" (tidigare "Finansiering och kriterier") och "Anslag" (tidigare "Uppföljning", visas bara för beviljade). Ny knapp "Kopiera till nästa år" uppe till höger: en ny post för samma utlysning med samma finansiär, regler, förvaltare, projekt och medsökande, alla datum ett år senare och årtal i namnet ett högre ("Forsknings-ALF 2027" blir 2028). Sökt och beviljat belopp, utfall, diarienummer, länk till ansökan och hela anslagsdelen lämnas tomma. Knappen fungerar även på låsta poster; originalet ändras inte. | Klar 2026-09-30 (#5) |
| F57 | Utlysningar och anslag, OH | OH är ett tal på varje sida. Finansiären har "Godkänd OH, högst (%)" (100 = full OH, 0 = ingen OH; ersätter valen Förvaltarens fulla OH / Högst / Ingen OH, som sparas som förut), undantag per förvaltare som ett tal, och ny "Prioriterad förvaltare". Förvaltaren har "OH som tas ut (%)" (tidigare "Förvaltarens fulla OH"). En organisation som både finansierar och förvaltar har båda fälten. Alla är förval: när finansiär eller förvaltare väljs i en post kopieras talen in i posten ("Finansiären godkänner OH, högst" och "Förvaltaren tar ut OH") och kan ändras där; en senare ändring på organisationen ändrar aldrig befintliga poster. Saknar posten förvaltare väljs finansiärens prioriterade förvaltare, annars "Förvald medelsförvaltare" under Inställningar > Hemorganisation. När förvaltaren tar ut mer än finansiären godkänner visar posten skillnaden och raden "Förvaltaren samfinansierar: Inte frågat / Ja / Nej" med datum. "Kopiera till nästa år" tar med postens tal men inte svaret. OH-fälten har två decimaler (21,95 %). | Klar 2026-09-30 (#5) |
| F58 | Data, engångsändring | Vid första start (beslut 2026-09-29): förvaltare utan "OH som tas ut" får årets OH ur sin egen lönekalkyl. Bara olåsta poster med status "Att söka" eller "Ej sökt" får OH-talen inskrivna. Låsta poster och poster som redan sökts ("Väntar svar", beslutade) ändras inte; deras nya fält står tomma och de räknas som förut. Ingenting raderas. | Klar 2026-09-30 (#5) |
| F59 | Utlysningar och anslag, rättelser | OH-reglerna som gäller när ansökan skickas in gäller hela perioden (beslut 2026-09-29): före inskickning följer posten organisationernas förval, när posten får sitt inskickningsdatum hämtas talen som gäller den dagen, och sedan ändras de inte. Tal som skrivits in för hand i posten skrivs aldrig över. Byts finansiär eller förvaltare och talen ändras, töms svaret om samfinansiering. Frågan om samfinansiering visas också när raden "Behov av samfinansiering" under lönebudgeten visar ett belopp. Förvaltare vars OH-period i lönekalkylen har slutat ger den senaste perioden. Låsta och redan inskickade poster räknas inte om när de öppnas (det ungefärliga beloppet ändrades eller tömdes förut). "Rensa beslut" tar bort beslutsdatum och status (posten stod kvar som Beviljat). "Antal år" läses som skrivet ("2–3" gav 23 år). Beloppsfält tar bort ören efter decimaltecken ("1 250 000,50" blev 100 gånger för stort). Engångsändringen läser postens visade status. | Klar 2026-09-30 (#5) |

## Omgång 9 – klar 2026-09-29 (#3)

| Nr | Område | Ändring | Status |
|---|---|---|---|
| F49 | Media, bilagor | Media-PDF:erna fanns kvar i "Media Appearance Files" men hittades inte. Orsaken var kontrollen av filnamn för bilagor, som nekade helt vanliga namn på ägarens Mac (men inte i GitHubs tester). Den kontrollen används också i reservvägarna för publikationer, granskningsintyg och konferensbidrag. Nu granskas namnet tecken för tecken, med samma regler: inga mappdelar, inget "%", inga styrtecken. Appen letar dessutom efter äldre mediabilagor under bilagans id, och filer i "Media Appearance Files" får inte vara genvägar. Datakvalitet visar "Saknar länkad PDF-fil" för mediaposter vars PDF inte hittas. | Klar 2026-09-29 (#3) |
| F50 | Undervisning | Listan över undervisningsuppdrag markerar vald rad som övriga listor (helt blå). Uppdrag med tillfällen som inte är bekräftade i Retendo (inga eller bara några) får en röd kant till vänster i stället för gul bakgrund, och kanten syns även när raden är vald. Uppdrag utan tillfällen markeras inte. | Klar 2026-09-29 (#3) |
| F51 | Organisationer | "Kopplade forskare" visas för alla organisationer, inte bara lärosäten. | Klar 2026-09-29 (#3) |
| F52 | Organisationer | Enhetsrutan har fältrubriken till vänster om fältet (svenskt namn, engelskt namn, ort). Under rutan listas forskarna vars affiliering, anställning eller utbildning pekar på enheten; ett klick på namnet öppnar forskaren. | Klar 2026-09-29 (#3) |

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
