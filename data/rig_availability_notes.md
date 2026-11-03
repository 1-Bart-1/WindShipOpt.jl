# Rig availability: what the record says and what the model does

Evidence on how often wing sails, Flettner rotors and towing kites are out of service, compiled November 2026, on one brief for all three rigs. The inputs are `wing_out_of_service`, `rotor_out_of_service` and `kite_out_of_service` in `data/assumptions.yaml`.

**Grades.** M: measured independently or by an operator with a stated method. O: operator statement without a method. C: maker claim or press release. E: someone's estimate or model. "Ours" marks our own arithmetic or judgement. Only sources read in full support a number below; class rules and long reports read in part appear as context, marked "part".

## Main result

No rig has an independently measured availability, failure rate, mean time between failures, repair time or repair cost. No published figure defines its denominator. The numbers below are too weak to tell the rigs apart: they show that a share of a few percent is what operators and makers report for wings and rotors, and nothing at all for kites.

| | Wing sail | Flettner rotor | Towing kite |
|---|---|---|---|
| Stated availability | 99.6 % (Canopée, 2 years, maker with owner, C); about 70 % "operation rate" on part of Shofu Maru's first voyage (O), which mixes wind, operations and faults | 99 % (Estraden trial, O), above 99 % (Estraden, C), 97 % usable (Estraden, about 6 years, O), above 95 % (Afros, 8.3 years, C) | none |
| Independent measurement | none | none; SSPA's Copenhagen report assumes "no down-time" (part) | none; the EU project reports savings only |
| Service experience, ours | about 30 ship-years, of which about 2 report anything | about 130-160 ship-years, of which about 14 report anything, all on rotors of 18 m or less | 14-25 ship-years installed, more than 1,800 h flown (C), about 0.2 ship-years of flying |
| Failure rate, repair time, repair cost | no record | no record | no record |
| Named faults | Shofu Maru limit switch, 2022, fixed aboard; Ashington, 1986-88, "significant downtime"; JAMDA ships, sails removed in the 1990s for maintenance cost and low fuel prices | Copenhagen vibration and icing, fixed, no durations; E-Ship 1's year out was its generators, not its rotors | Beluga SkySails: one system destroyed by deliberate overload, 2008; launch in heavy seas and foredeck durability named as short of need, 2009; parts replaced, Sep 2009 |
| Range the record can bear, ours | 0.4-10 % | 1-10 % | 1-50 % |

## Sources for the numbers

| Value | What it covers | Source | Grade |
|---|---|---|---|
| 97 % | Estraden, 2 rotors, about 6 years: "The Rotor Sails could be used 97% of the time"; denominator not given | Spliethoff Group Sustainability Report ed. 1, Norsepower Rotor Sail onboard MV Estraden, https://spliethoff-group.foleon.com/spliethoff-group-sustainability-report/spliethoff-group-sustainability-report-edition-1/norsepower-rotor-sail-onboard-mv-estraden | O |
| 99 % | Estraden, first rotor, trial from November 2014: "system availability was 99%" | Same | O |
| above 99 % | Estraden, to September 2018: "System availability exceeds 99%" | Kuuskoski, Norsepower, Naples Shipping Week 2018, https://2020.nsweek.com/wp-content/uploads/2018/10/Jukka_Norsepower.pdf | C |
| above 95 % | Afros, 4 rotors, January 2018 to April 2026, 154 voyages: "greater than 95% operational availability since installation" | Anemoi release in Cyprus Shipping News, 15 May 2026, https://cyprusshippingnews.com/2026/05/15/anemoi-rotor-sails-confirm-long-term-reliability-as-m-v-afros-completes-successful-second-dry-dock-survey/ | C |
| 99.6 % | Canopée, 4 wings, 2 years to June 2025: "99.6% of operational availability" | OceanWings 2025, https://www.oceanwings.com/news/two-years-four-oceanwings-one-clear-result-wind-propulsion-delivers | C |
| about 70 % | Shofu Maru, part of the maiden voyage, "sail operation rate"; not an availability | MOL via Ship & Bunker, https://shipandbunker.com/news/world/780389-mol-reports-wind-challenger-sail-operation-rate-of-70-on-maiden-voyage | O |
| more than 1,800 h, 1,200 flights | All SkySails kites to 2018 | SkySails 2018, https://utt.edu.tt/mtcc-caribbean/resources/2nd_eastern_regional/technology_providers/SkySails-Towing-Kite-Technology.pdf | C |
| 3-4 h/day | Beluga SkySails, first Atlantic leg, 2008, with extra maker engineers aboard; time in use, not availability | VerkehrsRundschau, 20 Feb 2008, https://www.verkehrsrundschau.de/nachrichten/transport-logistik/sky-sail-einsatz-erfolgreich-im-praxiseinsatz-3025027 | O |

Tallies of ship-years are ours, from listed installations, and assume each ship kept sailing with its rig; they are upper bounds per ship and incomplete.

## Failure modes

The published lists come from hazard work, not service records, so they say what could fail and not how often.

- **Wing:** automation fault, sensor loss, hydraulic leak, actuator jam, bearing failure, failure to stow in bad weather (MTF 2026 guideline, part). No flap, slewing or folding failure has been reported in service.
- **Rotor:** bearing temperature, vibration, ice, water ingress, fire at height, dropped objects (EMSA 2023 hazard study, part). A rotor stopped for about 24 h is flagged as a bearing risk, and its maker recommends idling at 3-5 rpm. No tilt, fold or rail failure has been reported. Bore expected "changing the bearings" as regular maintenance within about 20 years.
- **Kite:** launch in heavy seas and foredeck durability, in the words of the operator and maker. No canopy tear, tether break, control unit failure or kite in the water on a merchant ship has a date attached. Absence here means nobody published it; there is no reporting duty for any rig.

## Why low use is not low availability

Kites flew about 1-2.5 % of sea hours over the fleet's life (ours, with 250 sea days a year), and the three ships still fitted in 2016 did not use them. It would be wrong to read this as a share out of service. CE Delft (part) names "a combination of different factors": wind on the route, daylight at launch, short-haul economics, crew labour with rotating crews, and owners stopping. The first system's owner went insolvent in 2011, and both kite makers failed before any fleet aged. The model already limits the kite by wind and sea, and launch handling is priced per cycle. Commercial abandonment is a different risk from out of service, and the paper's discussion treats it there.

## The ship with the rig down

- **Route.** Class rules read (ABS 2020, BV NR206, MTF 2026; all part) treat the rig as auxiliary: the ship must be fully operable on its engines, with a manual route to a safe state. No source reports a ship unable to make its route because of a rig.
- **Drag.** Nobody has measured the drag of a locked wing, a stopped rotor or a stowed kite at full scale. The literature assumes C_D about 0.5 for a stopped rotor (SSPA, Reche-Vilanova, both part); the model's fit gives 0.64 at zero spin. A wing is feathered at no lift with its profile drag. A stowed kite adds nothing, because both makers retract or fold the mast; no number confirms this.
- **Several units.** Each rotor or wing has its own drive, but they share ship power, bridge control and wind sensors (EMSA, Anemoi, BV NR206; part), so a blackout stops all of them. No ship is on record running with one unit out, or losing all to one cause. A single kite has one tether, winch, mast and control unit, and no source records a spare canopy carried for service.
- **Repair.** Short fixes happen at sea (Shofu Maru). Larger ones wait for a port and a specialist. WASP (part) reports short yard repairs, spare-part delays and bespoke repair processes, with no ship or duration named. Time out of service depends on these logistics more than on the fault.
