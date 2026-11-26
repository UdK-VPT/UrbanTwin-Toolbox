# CO2OL ISLANDS – Datenquellen Berlin

**UrbanTwin Toolbox (UTT) · Quelleninventar · Version 13**

Grundlage: `ci-source-list-v12.csv`. Die Reihenfolge und Inhalte der 63 Einträge bleiben erhalten; räumliche und zeitliche Auflösung sind nicht dargestellt. Fehlende Angaben sind mit „—“ gekennzeichnet.

## Übersicht

| Klasse | Anzahl |
|---|---:|
| A – WFS-Dienste | 41 |
| B – WMS / Raster | 3 |
| C – Downloads / APIs | 2 |
| D – Quellenklärung / Zugang | 11 |
| E – Abgeleitete Daten / Curation | 1 |
| F – Unabhängige Datendienste / zurückgestellt | 5 |
| **Gesamt** | **63** |

## A – WFS-Dienste (41)

| Nr. | Parameterbezeichnung | Kategorie | Nutzung / Zweck | Mögliche Datenquelle | Datenformat | URL |
|---:|---|---|---|---|---|---|
| 1 | ALKIS Berlin - Gesamtdatensatz | Gebäude | Amtliche Gebäudedaten | Geoportal Berlin - ALKIS Berlin | WFS | [GetCapabilities](https://gdi.berlin.de/services/wfs/alkis?request=GetCapabilities&service=WFS) |
| 2 | ALKIS Berlin Gebäude | Gebäude | Gebäudegrundrisse, Gebäudefunktion und Geschosszahl | Geoportal Berlin – ALKIS | WFS | [GetCapabilities](https://gdi.berlin.de/services/wfs/alkis_gebaeude?request=GetCapabilities&service=WFS) |
| 3 | ALKIS Berlin Flurstücke | Geobasisdaten | Flurstücksgeometrien und Katasterbezug | Geoportal Berlin – ALKIS | WFS | [GetCapabilities](https://gdi.berlin.de/services/wfs/alkis_flurstuecke?request=GetCapabilities&service=WFS) |
| 4 | Statistische Einheiten im INSPIRE-Datenmodell (RBS-Blöcke) | Geobasisdaten | Räumlicher Bezug auf Blockebene | Amt für Statistik Berlin-Brandenburg | WFS | [GetCapabilities](https://gdi.berlin.de/services/wfs/su_blk?request=GetCapabilities&service=WFS) |
| 5 | Adressen Regionales Bezugssystem (RBS) | Geobasisdaten | Adressbezug für Gebäude | Geoportal Berlin – RBS | WFS | [GetCapabilities](https://gdi.berlin.de/services/wfs/adressen_rbs?request=GetCapabilities&service=WFS) |
| 6 | Gebäudehöhen (Umweltatlas) | Gebäude | Firsthöhe, Dachform und Geschosszahl | Umweltatlas Berlin – LoD2 | WFS | [GetCapabilities](https://gdi.berlin.de/services/wfs/ua_gebaeudehoehen?request=GetCapabilities&service=WFS) |
| 7 | Stadtstruktur (Umweltatlas) – ab 2021 | Stadtstruktur | Baustrukturtypen und Freiraumstruktur | Umweltatlas Berlin | WFS | [GetCapabilities](https://gdi.berlin.de/services/wfs/ua_stadtstruktur?request=GetCapabilities&service=WFS) |
| 8 | Städtebauliche Dichte – GFZ/GRZ 2019 | Stadtstruktur | Grundflächenzahl und Geschossflächenzahl | Umweltatlas Berlin | WFS | [GetCapabilities](https://gdi.berlin.de/services/wfs/ua_staedtebauliche_dichte2019?request=GetCapabilities&service=WFS) |
| 9 | Verkehrsflächen (Straßenbreite) | Infrastruktur | Platz für Trassen, Breite je Abschnitt | ALKIS Berlin, Layer alkis:tatsaechlichenutzungflaechen | WFS 2.0 | [GetCapabilities](https://gdi.berlin.de/services/wfs/alkis?SERVICE=WFS&REQUEST=GetCapabilities) |
| 10 | Straßenabschnitte (Geometrie, Länge, Hauptnetz ja/nein) | Infrastruktur | Trassen für Kältenetz-Bilanz | Detailnetz Berlin, Layer detailnetz:c_strassenabschnitte | WFS 2.0 (GeoJSON/GML), EPSG:25833 | [GetCapabilities](https://gdi.berlin.de/services/wfs/detailnetz?SERVICE=WFS&REQUEST=GetCapabilities) |
| 11 | Wasserschutzgebiete | Grundwasser | Restriktionsbehaftete Flächen | Geoportal Berlin | Shape | [GetCapabilities](https://gdi.berlin.de/services/wfs/wsg?request=GetCapabilities&service=WFS) |
| 12 | Wärmeplan | Infrastruktur / Regulierung | Konkurrenz / Integration | Geoportal Berlin | shape | [GetCapabilities](https://gdi.berlin.de/services/wfs/waermeplanung?request=GetCapabilities&service=WFS) |
| 13 | Nahwärmenetze | Infrastruktur | Konkurrenz / Integration | Geoportal Berlin | Shape | [GetCapabilities](https://gdi.berlin.de/services/wfs/waermeplanung?request=GetCapabilities&service=WFS) |
| 14 | Gebäudealter der Wohnbebauung (Blockalterskarte) | Gebäude | Gebäudealterbestimmung | Geoportal Berlin | WFS | [GetCapabilities](https://gdi.berlin.de/services/wfs/ua_gebaeudealter?request=GetCapabilities&service=WFS) |
| 15 | Landeseigentum (Bezirk, Hauptverwaltung, andere Bereiche) | Eigentum | öffentliche Hand als Ansprechpartner | Berliner Landesgrundvermögen, 3 Layer | WFS 2.0 | [GetCapabilities](https://gdi.berlin.de/services/wfs/landesgrundvermoegen?SERVICE=WFS&REQUEST=GetCapabilities) |
| 16 | Eigentümerstruktur (Einzelpersonen, juristische Personen, städtische WBG, Genossenschaften, Gemeinwohl) | Eigentum | Anteile je Gebiet | Eigentumskonzentration Berlin, 6 Layer | WFS 2.0 | [GetCapabilities](https://gdi.berlin.de/services/wfs/eigentumstruktur?SERVICE=WFS&REQUEST=GetCapabilities) |
| 17 | PV-Potenzial Dach (kWp, kWh/a) | Erzeugung | Erzeugung, Eigenverbrauch | Solarpotenzial Solarrechner, Layer d_photovoltaik_potenzial (mit ALKIS-ID) | WFS 2.0 | [GetCapabilities](https://gdi.berlin.de/services/wfs/ua_solarpotenzial_solarrechner?SERVICE=WFS&REQUEST=GetCapabilities) |
| 18 | PV-Bestand (kWp) | Erzeugung | installierte Leistung | Solaranlagen PV, 3 Layer (> 30 kWp, öffentliche Hand, ≤ 30 kWp je PLZ) | WFS 2.0 | [GetCapabilities](https://gdi.berlin.de/services/wfs/ua_solaranlagen_pv?SERVICE=WFS&REQUEST=GetCapabilities) |
| 19 | Altlasteninformationen | Grundwasser | Eignung geothermischer Nutzung, Restriktionen | Geoportal Berlin | shape | [GetCapabilities](https://gdi.berlin.de/services/wfs/ua_bodengesellschaften_2020?request=GetCapabilities&service=WFS) |
| 20 | spezifische Wärmeleitfähigkeit, spezifische Entzugsleistung, Restriktionen (Wasserschutzgebiete, Bereiche mit artesisch gespanntem Grundwasser, Grundwasserleiter 2, 3und 4), Bohrpunkte | Geothermisches Potenzial | standortspezifische Auskünfte zum geothermischen Potenzial | Geoportal Berlin | — | — |
| 21 | Oberflächentemperatur (2022) | Oberfläche/Klima | urbane Wärmeinsel | Umweltatlas Berlin – Klimaanalysekarten 2022 | — | — |
| 22 | Versiegelung (2021) | Oberfläche/Klima | urbane Wärmeinsel, Infiltration und Oberflächenbilanz | Umweltatlas Berlin – Versiegelung 2021 | WFS | [GetCapabilities](https://gdi.berlin.de/services/wfs/ua_versiegelung_2021?SERVICE=WFS&REQUEST=GetCapabilities) |
| 23 | Denkmalkarte Berlin | Regulierung | Denkmalschutz, bauliche Restriktionen | Landesdenkmalamt Berlin | WFS | [GetCapabilities](https://gdi.berlin.de/services/wfs/denkmale?request=GetCapabilities&service=WFS) |
| 24 | Grundwasserflurabstand 2020 | Grundwasser | Grundwasserflurabstand, ergänzende Vektordaten | Geoportal Berlin | WFS | [GetCapabilities](https://gdi.berlin.de/services/wfs/ua_flurabstand_2020?request=GetCapabilities&service=WFS) |
| 25 | Grundwassergleichen 2020 | Grundwasser | Grundwasserstand und hydraulische Randbedingungen | Geoportal Berlin | WFS | [GetCapabilities](https://gdi.berlin.de/services/wfs/ua_grundwassergl_2020?request=GetCapabilities&service=WFS) |
| 26 | Grundwassermessstellen | Grundwasser | Lage von Grundwassermessstellen | Geoportal Berlin | WFS | [GetCapabilities](https://gdi.berlin.de/services/wfs/gwm?request=GetCapabilities&service=WFS) |
| 27 | Grundwassergüte 2000 | Grundwasser | Grundwasserqualität | Geoportal Berlin | WFS | [GetCapabilities](https://gdi.berlin.de/services/wfs/ua_grundwasserguete_2000?request=GetCapabilities&service=WFS) |
| 28 | Grundwassertemperatur 2024 | Grundwasser | Wärmequellenpotenzial | Geoportal Berlin | WFS | [GetCapabilities](https://gdi.berlin.de/services/wfs/ua_grundwassertemperatur_2024?request=GetCapabilities&service=WFS) |
| 29 | Grundwasserneubildung 2022 | Grundwasser | Grundwasserneubildung | Geoportal Berlin | WFS | [GetCapabilities](https://gdi.berlin.de/services/wfs/ua_grundwasserneubildung_2022?request=GetCapabilities&service=WFS) |
| 30 | Geologische Bohrdaten | Geologie | Bohrdaten und Verweise auf Bohrprofile | Geoportal Berlin | WFS | [GetCapabilities](https://gdi.berlin.de/services/wfs/bohrdaten?request=GetCapabilities&service=WFS) |
| 31 | Geologische Schnitte | Geologie | Schichtenaufbau und Untergrundmodell | Geoportal Berlin | WFS | [GetCapabilities](https://gdi.berlin.de/services/wfs/geol_schnitte?request=GetCapabilities&service=WFS) |
| 32 | Wasserdurchlässigkeit des Untergrundes | Geologie | Hydraulische Eigenschaften des Untergrundes | Geoportal Berlin | WFS | [GetCapabilities](https://gdi.berlin.de/services/wfs/ua_wasserdurchlaessigkeit?request=GetCapabilities&service=WFS) |
| 33 | Bohrtiefen der oberflächennahen Geothermie | Geologie | Bohrtiefen und wasserrechtliche Restriktionen | Geoportal Berlin | WFS | [GetCapabilities](https://gdi.berlin.de/services/wfs/geologie_rupelton?request=GetCapabilities&service=WFS) |
| 34 | Flächennutzung – ab 2021 | Oberfläche/Klima | Landnutzung und Oberflächenbilanz | Geoportal Berlin | WFS | [GetCapabilities](https://gdi.berlin.de/services/wfs/ua_flaechennutzung?request=GetCapabilities&service=WFS) |
| 35 | Baumbestand Berlin | Oberfläche/Klima | Lage bestehender Bäume | Geoportal Berlin | WFS | [GetCapabilities](https://gdi.berlin.de/services/wfs/baumbestand?request=GetCapabilities&service=WFS) |
| 36 | Energienetze | Infrastruktur | Räumliche Abdeckung von Fernwärme- und Gasnetzen | Geoportal Berlin | WFS | [GetCapabilities](https://gdi.berlin.de/services/wfs/ea_energienetze?request=GetCapabilities&service=WFS) |
| 37 | Energieverbrauch – Fernwärme | Verbrauch | Räumlich aggregierter Fernwärmeverbrauch | Geoportal Berlin | WFS | [GetCapabilities](https://gdi.berlin.de/services/wfs/ua_fernwaerme?request=GetCapabilities&service=WFS) |
| 38 | Energieverbrauch – Strom | Verbrauch | Räumlich aggregierter Stromverbrauch | Energieatlas Berlin / Geoportal Berlin | WFS | [GetCapabilities](https://gdi.berlin.de/services/wfs/ua_stromverbrauch?request=GetCapabilities&service=WFS) |
| 39 | Energieverbrauch – Gas | Verbrauch | Räumlich aggregierter Gasverbrauch | Energieatlas Berlin / Geoportal Berlin | WFS | [GetCapabilities](https://gdi.berlin.de/services/wfs/ua_gas?request=GetCapabilities&service=WFS) |
| 40 | Geothermie – Summe der Anlagen | Geothermisches Potenzial | Bestand geothermischer Anlagen | Geoportal Berlin | WFS | [GetCapabilities](https://gdi.berlin.de/services/wfs/ea_geothermie?request=GetCapabilities&service=WFS) |
| 41 | Filtervermögen der Böden 2020 | Geologie | Wasserdurchlässigkeit der Böden (kf-Wert) | Geoportal Berlin | WFS | [GetCapabilities](https://gdi.berlin.de/services/wfs/ua_boden_filter_2020?request=GetCapabilities&service=WFS) |

## B – WMS / Raster (3)

| Nr. | Parameterbezeichnung | Kategorie | Nutzung / Zweck | Mögliche Datenquelle | Datenformat | URL |
|---:|---|---|---|---|---|---|
| 42 | Gebäudealter (1992/93) | Gebäude | Gebäudealterbestimmung | Geoportal Berlin | WMS | [GetCapabilities](https://gdi.berlin.de/services/wms/staedtebauliche_entwicklung?SERVICE=WMS&REQUEST=GetCapabilities) |
| 43 | Oberflächentemperatur (2022, Raster) | Oberfläche/Klima | urbane Wärmeinsel | Umweltatlas Berlin – Klimaanalysekarten 2022 | — | — |
| 44 | Versiegelung (2021, unkorrigiertes Raster) | Oberfläche/Klima | urbane Wärmeinsel, Infiltration und Oberflächenbilanz | Umweltatlas Berlin – Versiegelung 2021 | Raster / ATOM | [Quelle](https://gdi.berlin.de/data/ua_versiegelung_2021/atom/) |

## C – Downloads / APIs (2)

| Nr. | Parameterbezeichnung | Kategorie | Nutzung / Zweck | Mögliche Datenquelle | Datenformat | URL |
|---:|---|---|---|---|---|---|
| 45 | Zensus 2022 – Gebäude-, Wohnungs- und Bevölkerungsstatistik | Gebäude | Statistische Grundlage für Gebäude, Wohnen, Bevölkerung, Heizungsarten und weitere verfügbare Gitterthemen | Statistisches Bundesamt – Zensus 2022 | — | — |
| 46 | LUP Gebäudealterskarte | Gebäude | Gebäudealterbestimmung | Datenbestand aus anderem Projekt (LUP) | — | — |

## D – Quellenklärung / Zugang (11)

| Nr. | Parameterbezeichnung | Kategorie | Nutzung / Zweck | Mögliche Datenquelle | Datenformat | URL |
|---:|---|---|---|---|---|---|
| 47 | Grundwasserstand | Grundwasser | hydraulische Randbedingungen für Simulation | Geoportal Berlin | CSV, Shape | — |
| 48 | Grundwasserfließrichtung | Grundwasser | thermische Fahnenausbreitung, Brunnenanordnung | Geoportal Berlin | Shape, Raster | — |
| 49 | Grundwasserfließgeschwindigkeit | Grundwasser | Transportmodellierung | Geoportal Berlin / Landesmessnetz | Shape, CSV | — |
| 50 | Schichtenaufbau | Geologie | Bohrsimulation / Untergrundmodell | Geoportal Berlin / Geologischer Dienst | Shape, Bohrprofile | — |
| 51 | Wärmeleitfähigkeit λ | Geologie | Untergrundsimulation | Geologischer Dienst / Literatur | Tabelle, GIS | — |
| 52 | hydraulische Leitfähigkeit (kf-Wert) | Geologie | Brunnenleistung | Geoportal / Bohrprofile | Tabelle | — |
| 53 | Lage bestehender Brunnen / geothermische Anlagen | Infrastruktur | Nutzungskonflikte | Landesdaten / Bohrdaten | Shape | — |
| 54 | Ver- und Entsorgungsleitungen | Infrastruktur | Konfliktprüfung | Netzbetreiber / infreSt Leitungsauskunftsportal | — | [Quelle](https://www.infrest.de/) |
| 55 | Abwärmepotenzial (Menge, Temperatur) | Energie | Abwärmenutzung, auch Rechenzentren | Plattform für Abwärme nach Energieeffizienzgesetz | prüfen | [Quelle](https://www.bfee-online.de/BfEE/DE/Effizienzpolitik/Plattform_fuer_Abwaerme/plattform_fuer_abwaerme_node.html) |
| 56 | Rechenzentren (Anschlussleistung, Energieverbrauch) | Energie | Kältelast genauer als nur Lage | Rechenzentrumsregister nach Energieeffizienzgesetz (prüfen, was öffentlich ist) | prüfen | — |
| 57 | Altlasteninformationen | Grundwasser | Eignung geothermischer Nutzung, Restriktionen | interne Projektdaten | CSV? | — |

## E – Abgeleitete Daten / Curation (1)

| Nr. | Parameterbezeichnung | Kategorie | Nutzung / Zweck | Mögliche Datenquelle | Datenformat | URL |
|---:|---|---|---|---|---|---|
| 58 | Straßengraph und Hausanschluss je Gebäude (Länge) | Infrastruktur | Netzlast je Abschnitt, Anschlusslängen | abgeleitet aus Detailnetz + Gebäuden (bei mir lokal: 406.375 Gebäude, Mittel 24 m) | PostGIS-Tabellen | — |

## F – Unabhängige Datendienste / zurückgestellt (5)

| Nr. | Parameterbezeichnung | Kategorie | Nutzung / Zweck | Mögliche Datenquelle | Datenformat | URL |
|---:|---|---|---|---|---|---|
| 59 | Rechenzentren (Lage, Betreiber) | Energie | Kältelast, Abwärme | PeeringDB + OpenStreetMap (bei mir 23 Gebäude) | JSON-API | [Quelle](https://www.peeringdb.com/api/fac?country=DE&city__contains=Berlin) |
| 60 | Meteorologische Randbedingungen (HOSTRADA, 11 Variablen) | Oberfläche/Klima | Randbedingung Gebäudesimulation | DWD HOSTRADA / lokales QNAP-Archiv / hostrada4py | NetCDF / Dienstschnittstelle (geplant) | [Quelle](https://opendata.dwd.de/climate_environment/CDC/grids_germany/hourly/hostrada/) |
| 61 | Niederschlag | Oberfläche/Klima | Grundwasserneubildung | DWD | CSV | — |
| 62 | OpenStreetMap (OSM) – Berlin | Geobasisdaten | Generische UTT-Standardquelle (geplant) | — | — | — |
| 63 | Stromnetz / Umspannwerke | Infrastruktur | Stromnetzinfrastruktur | — | — | — |
