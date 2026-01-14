# DPS Transit System Architecture

This document contains the complete system architecture and diagrams for the DPS Transit multi-modal transportation system.

---

## System Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         DPS TRANSIT SYSTEM                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  LIGHT RAIL (Track 3) - LS Metro                                           │
│  ─────────────────────────────────                                          │
│  Model: metrotrain / metrotrain2 (replacement)                              │
│  Route: Urban LS underground/elevated                                       │
│  Service: High frequency metro                                              │
│                                                                             │
│  ════════════════════════════════════════════════════════════════════════  │
│                                                                             │
│  REGIONAL PASSENGER (Track 0) - Main Line                                  │
│  ────────────────────────────────────────                                   │
│  Models: streakcoaster + streakc (BigDaddy passenger)                       │
│  Route: LSIA → Davis → Downtown → Del Perro → Sandy → Paleto               │
│  Service: 70% Passenger / 30% Freight                                       │
│                                                                             │
│  FREIGHT (Track 0) - Main Line                                             │
│  ─────────────────────────────                                              │
│  Models: sd70mac + freight cars (BigDaddy)                                  │
│  Route: Same track, mixed into schedule                                     │
│                                                                             │
│  ════════════════════════════════════════════════════════════════════════  │
│                                                                             │
│  ROXWOOD SERVICE (Track 13)                                                │
│  ──────────────────────────                                                 │
│  Models: TBD (passenger + freight)                                          │
│  Route: Roxwood expansion area                                              │
│  Service: 70% Passenger / 30% Freight                                       │
│                                                                             │
│  ════════════════════════════════════════════════════════════════════════  │
│                                                                             │
│  SHUTTLE BUSES - Connections                                               │
│  ───────────────────────────                                                │
│  AI-driven shuttles between:                                                │
│  • Light Rail ↔ Regional stations (in LS)                                  │
│  • Paleto ↔ Roxwood (cross-expansion link)                                 │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Three Separate Train Networks

The GTA V map has three train track systems that do NOT intersect at convenient stations:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        SAN ANDREAS TRANSIT NETWORKS                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. LS METRO (Track 3) - Blue urban light rail                             │
│     ├── Contained within Los Santos city                                    │
│     ├── Multiple stops: Downtown, Del Perro, Airport area                  │
│     └── Does NOT leave the city                                            │
│                                                                             │
│  2. REGIONAL RAIL (Track 0) - Red line around main island                  │
│     ├── LSIA → Davis → Downtown → Del Perro                                │
│     ├── Up coast → Sandy Shores → Grapeseed → Paleto Bay                   │
│     └── Loops back - but NO connection to Roxwood                          │
│                                                                             │
│  3. ROXWOOD RAIL (Track 13) - Expansion area                               │
│     ├── Railroad (blue) - Freight/regional through Roxwood County          │
│     ├── BART (red) - Light rail: Roxwood City, Bay Area, Whetstone         │
│     ├── Key stops: Int'l Airport, Roxwood City, Garlicville,               │
│     │              Ding Dong Station, Sycamore, Whetstone City             │
│     └── Completely isolated from main island rail                          │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                         SHUTTLE BUS CONNECTIONS NEEDED                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  GAP 1: LS Metro ↔ Regional Rail (within Los Santos)                       │
│         Example: Metro stop near Union Depot ↔ Regional station            │
│                                                                             │
│  GAP 2: Paleto Bay (Regional terminus) ↔ Roxwood entry point               │
│         This is the BIG gap - crosses into expansion territory             │
│                                                                             │
│  GAP 3: Within Roxwood - Railroad ↔ BART connections                       │
│         If those don't share stations either                               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Complete Transit Network with Shuttle Routes

```
┌─────────────────────────────────────────────────────────────────────────────┐
│              COMPLETE DPS TRANSIT NETWORK - BASED ON ALL 3 MAPS            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                              PALETO BAY                                     │
│                            ┌───────────┐                                    │
│                            │ Paleto E  │                                    │
│                            │ Paleto W  │ ←── REGIONAL RAIL (Track 0)       │
│                            │Paleto Frst│     Northern Terminus              │
│                            └─────┬─────┘                                    │
│                                  │                                          │
│                            [SHUTTLE A]                                      │
│                            Paleto ↔ Roxwood                                 │
│                                  │                                          │
│  ════════════════════════════════╪══════════════════════════════════════   │
│           ROXWOOD EXPANSION      │      (Crosses Paleto River)              │
│  ════════════════════════════════╪══════════════════════════════════════   │
│                                  ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                     ROXWOOD COUNTY RAIL                              │   │
│  │                                                                      │   │
│  │   RAILROAD (Track 13 - Blue)         BART (Light Rail - Red)        │   │
│  │   ──────────────────────             ───────────────────────        │   │
│  │   Marina Beach                       Whetstone City                  │   │
│  │      ↓                                  ↓                            │   │
│  │   Sycamore ◄────[SHUTTLE B]────► Angel Pine                         │   │
│  │      ↓                                  ↓                            │   │
│  │   Ding Dong Station                 Portmanteau                      │   │
│  │      ↓                                  ↓                            │   │
│  │   Garlicville ◄───[SHUTTLE C]───► Whetstone County stops            │   │
│  │      ↓                                                               │   │
│  │   Roxwood City ◄══════════════════► Roxwood City (SHARED HUB?)      │   │
│  │      ↓                                  ↓                            │   │
│  │   Int'l Airport ◄─────────────────► Bay Area                        │   │
│  │      ↓                                  ↓                            │   │
│  │   Foster Valley                     Foster Valley                    │   │
│  │      ↓                                                               │   │
│  │   Haywire / North Roxwood                                           │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ════════════════════════════════════════════════════════════════════════  │
│                          MAIN ISLAND (San Andreas)                          │
│  ════════════════════════════════════════════════════════════════════════  │
│                                                                             │
│  REGIONAL RAIL (Track 0 - Red)              LS METRO (Track 3 - Blue)      │
│  ─────────────────────────────              ─────────────────────────      │
│                                                                             │
│       Paleto Bay ←── north terminus                                        │
│           ↓                                                                 │
│       Grapeseed                                                            │
│           ↓                                                                 │
│       Sandy Shores                                                         │
│           ↓                                                                 │
│       Palmer-Taylor                                                        │
│           ↓                                                                 │
│       Mirror Park ◄────[SHUTTLE D]────► Mirror Park Metro?                 │
│           ↓                                                                 │
│       DOWNTOWN LS ◄════[SHUTTLE E]════► DOWNTOWN Metro (Union Depot)       │
│       (Union Depot)                      Multiple Metro stops              │
│           ↓                                  ↓                              │
│       Del Perro ◄──────[SHUTTLE F]──────► Del Perro Metro                  │
│           ↓                                  ↓                              │
│       Davis ◄──────────[SHUTTLE G]──────► Davis Metro                      │
│           ↓                                  ↓                              │
│       LSIA ◄═══════════[SHUTTLE H]═══════► LSIA Metro                      │
│       (Regional)                           (Light Rail Terminal)           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Proposed Shuttle Routes

| Route | From | To | Purpose |
|-------|------|-----|---------|
| **A** | Paleto Bay (Regional) | Marina Beach/Sycamore (Roxwood Railroad) | **CRITICAL** - Only link to Roxwood |
| **B** | Sycamore (Railroad) | Angel Pine (BART) | Cross-system Roxwood transfer |
| **C** | Garlicville (Railroad) | Whetstone County (BART) | Mid-Roxwood transfer |
| **D** | Mirror Park (Regional) | Nearest Metro stop | East LS connection |
| **E** | Union Depot (Regional) | Downtown Metro | **MAIN HUB** - Central LS |
| **F** | Del Perro (Regional) | Del Perro Metro | West LS connection |
| **G** | Davis (Regional) | Davis Metro | South LS connection |
| **H** | LSIA Regional | LSIA Metro Terminal | **AIRPORT HUB** |

---

## Example Player Journey: LSIA → North Roxwood

```
START: Los Santos International Airport
                    │
    ┌───────────────┴───────────────┐
    │  OPTION A          OPTION B   │
    │  (Metro)           (Regional) │
    ▼                    ▼
LS Metro ────────► Regional Rail
    │              at LSIA
    │                    │
    ▼                    │
Davis Metro              │
    │                    │
[SHUTTLE G]              │
    │                    │
    ▼                    │
Davis Regional ◄─────────┘
    │
    ▼
Regional Rail north
    │
    ▼
Paleto Bay (end of line)
    │
[SHUTTLE A] ←── Cross to Roxwood
    │
    ▼
Marina Beach / Sycamore
(Roxwood Railroad)
    │
    ▼
Roxwood Railroad north
    │
    ▼
Haywire / North Roxwood

END: North Roxwood County
```

---

## Track Index Mapping

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  TRACK    │ ROUTE                              │ TRAIN TYPES                │
│───────────┼────────────────────────────────────┼────────────────────────────│
│  0        │ Main island loop                   │ Regional + Freight (70/30) │
│           │ LSIA → Davis → Downtown →          │ streakcoaster + sd70mac    │
│           │ Del Perro → Sandy → Grapeseed →    │                            │
│           │ Paleto → loops back                │                            │
│───────────┼────────────────────────────────────┼────────────────────────────│
│  3        │ LS Metro (urban)                   │ Light Rail                 │
│           │ Underground + elevated in LS       │ metrotrain (or alt model)  │
│───────────┼────────────────────────────────────┼────────────────────────────│
│  13       │ Roxwood expansion                  │ Regional + Freight (70/30) │
│           │ (Custom track via amb-roxwood)     │ Custom passenger + sd70mac │
│───────────┼────────────────────────────────────┼────────────────────────────│
│  1,2,4-12 │ Disabled / unused                  │ N/A                        │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Available Train Models

### Locomotives / Engines

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           LOCOMOTIVES / ENGINES                             │
├─────────────────────────────────────────────────────────────────────────────┤
│  MODEL              │ TYPE              │ USE CASE                          │
│─────────────────────┼───────────────────┼───────────────────────────────────│
│  sd70mac            │ Diesel Freight    │ Freight trains (modern)           │
│  gevo               │ Diesel Freight    │ Freight trains (GE Evolution)     │
│  streak             │ Amtrak-style      │ Regional passenger                │
│  streak42           │ Amtrak variant    │ Regional passenger                │
│  streakclassic      │ Classic Amtrak    │ Regional passenger                │
│  streakcoaster      │ Commuter          │ Commuter/regional passenger       │
│  freight            │ Native GTA        │ Basic freight loco                │
│  freightc           │ Native variant    │ Basic freight loco                │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Passenger Cars

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          PASSENGER CARS                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│  MODEL              │ CAPACITY          │ USE CASE                          │
│─────────────────────┼───────────────────┼───────────────────────────────────│
│  metrotrain         │ 4 peds            │ LS Metro / Light Rail (native)    │
│  streakc            │ 7 peds            │ Regional passenger cars           │
│  streakcab          │ 7 peds            │ Passenger cab car                 │
│  streakcoasterc     │ 10 peds           │ Coaster commuter cars             │
│  streakcoastercab   │ 7 peds            │ Coaster cab car                   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Freight Cars

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           FREIGHT CARS                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│  freightboxlarge    │ freightcont       │ freightstack    │ freightcaboose  │
│  freightbox         │ freighttankbulk   │ freightgondola  │ foxbox          │
│  freightflat        │ freighttanklong   │ freightgraincar │                 │
│  freightflatlogs    │ freightcoal       │ freighthopper   │                 │
│  freightflattank    │ freightrack       │ freightbeam/c   │                 │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 70/30 Schedule Concept

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    REGIONAL LINE (Track 0) - HOURLY CYCLE                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  TIME      TRAIN TYPE       MODEL CONFIG                                    │
│  ────────────────────────────────────────────────────────────────────────   │
│  :00       PASSENGER        streakcoaster + 5x streakc                      │
│  :10       PASSENGER        streakcoaster + 3x streakc                      │
│  :20       FREIGHT          sd70mac + mixed freight cars                    │
│  :30       PASSENGER        streakcoaster + 5x streakc                      │
│  :40       PASSENGER        streakcoaster + 3x streakc                      │
│  :50       PASSENGER        streakcoaster + 5x streakc                      │
│                                                                             │
│  Result: 5 passenger (70%) + 1 freight (30%) per hour                       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Custom Train Models (To Fix)

### metrotrain2 (Light Rail Replacement)

**Status:** Door collision broken - players can walk through doors

**Files:**
- `metrotrain2.yft` - Vehicle model
- `metrotrain2.ytd` - Textures
- `metrotrain2_hi.yft` - High LOD model

**Issue:** Files are named `metrotrain2` but need to be named `metrotrain` to replace the native model via streaming.

**Fix Options:**
1. Rename files to `metrotrain.*` for direct replacement
2. Fix collision mesh in ZModeler3/OpenIV
3. Use native metrotrain until fixed

---

## Dependencies

| Resource | Purpose | Required |
|----------|---------|----------|
| qb-core | Framework, economy, player management | Yes |
| ox_lib | UI components, callbacks, notifications | Yes |
| ox_target | Interactive zones at stations | Yes |
| oxmysql | Database (optional) | No |
| qs-inventory | Persistent ticket items | Optional |
| xsound | Audio announcements | Optional |
| BigDaddy-Trains | Custom train models and configs | Recommended |
| amb-roxwood-trains | Roxwood track data | Required for Zone C |

---

## Reference Resources

Located in `F:\Server\Script Dev`:

| Resource | Status | Useful For |
|----------|--------|------------|
| Ehbw-Trains | Configs open, core obfuscated | Export API patterns, track/train configs |
| BigDaddy-Trains | DLLs obfuscated | Asset files, trains.xml, framework patterns |
| jim-trains | Client obfuscated | Ticket logic, station locations |
| nteam_train_scenario | Mostly obfuscated | Scenario/cutscene patterns |

---

*Last Updated: 2026-01-01*
