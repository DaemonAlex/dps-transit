# DPS Transit System Architecture

This document contains the system architecture and diagrams for the DPS Transit multi-modal transportation system.

> Note: The former expansion service was removed in v2.8.0. The passenger network
> now runs entirely on the main island: Regional Rail (Track 0) and LS Metro
> (Track 3), with Sandy Shores / Grapeseed freight sidings on Track 12.

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
│  Route: LSIA → Davis → Downtown → Del Perro → Paleto Junction              │
│  Service: 70% Passenger / 30% Freight                                       │
│                                                                             │
│  FREIGHT (Track 0 / Track 12) - Main Line + Sidings                        │
│  ────────────────────────────────────────────────                          │
│  Models: sd70mac + freight cars (BigDaddy)                                  │
│  Route: Track 0 mixed schedule; Sandy Shores / Grapeseed sidings on Tk 12  │
│                                                                             │
│  ════════════════════════════════════════════════════════════════════════  │
│                                                                             │
│  SHUTTLE BUSES - Connections                                               │
│  ───────────────────────────                                                │
│  AI-driven shuttles between Light Rail ↔ Regional stations (in LS)          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Main Island Rail Networks

The GTA V map has two train track systems used by this resource. They do NOT
intersect at convenient stations, so shuttle buses bridge the gaps.

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
│     ├── Up coast → Paleto Junction (northern terminus)                     │
│     └── Sandy Shores / Grapeseed freight sidings (Track 12) branch east    │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                         SHUTTLE BUS CONNECTIONS                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  LS Metro ↔ Regional Rail (within Los Santos)                              │
│     Example: Metro stop near Union Depot ↔ Regional station                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Complete Transit Network with Shuttle Routes

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          MAIN ISLAND (San Andreas)                          │
│  ════════════════════════════════════════════════════════════════════════  │
│                                                                             │
│  REGIONAL RAIL (Track 0 - Red)              LS METRO (Track 3 - Blue)      │
│  ─────────────────────────────              ─────────────────────────      │
│                                                                             │
│       Paleto Junction ←── north terminus                                   │
│           ↓                                                                 │
│       (Sandy Shores / Grapeseed freight sidings, Track 12, branch east)    │
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

## Shuttle Routes

| Route | From | To | Purpose |
|-------|------|-----|---------|
| **D** | Mirror Park (Regional) | Nearest Metro stop | East LS connection |
| **E** | Union Depot (Regional) | Downtown Metro | **MAIN HUB** - Central LS |
| **F** | Del Perro (Regional) | Del Perro Metro | West LS connection |
| **G** | Davis (Regional) | Davis Metro | South LS connection |
| **H** | LSIA Regional | LSIA Metro Terminal | **AIRPORT HUB** |

> Routes D-H are gated on the metro stations being defined; the metro line ships
> disabled until those station coordinates are added (see `config/trains.lua`).

---

## Track Index Mapping

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  TRACK    │ ROUTE                              │ TRAIN TYPES                │
│───────────┼────────────────────────────────────┼────────────────────────────│
│  0        │ Main island line                   │ Regional + Freight (70/30) │
│           │ LSIA → Davis → Downtown →          │ streakcoaster + sd70mac    │
│           │ Del Perro → Paleto Junction        │                            │
│───────────┼────────────────────────────────────┼────────────────────────────│
│  3        │ LS Metro (urban)                   │ Light Rail                 │
│           │ Underground + elevated in LS       │ metrotrain (or alt model)  │
│───────────┼────────────────────────────────────┼────────────────────────────│
│  12       │ Sandy Shores / Grapeseed sidings   │ Freight only               │
│           │ (branch east of Paleto Junction)   │ sd70mac + freight cars     │
│───────────┼────────────────────────────────────┼────────────────────────────│
│  1,2,4-11 │ Disabled / unused                  │ N/A                        │
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
| qbx_core (or qb-core / es_extended) | Framework, economy, player management | Yes |
| ox_lib | UI components, callbacks, notifications | Yes |
| ox_target | Interactive zones at stations | Yes |
| oxmysql | Database (optional) | No |
| ox_inventory / qs-inventory | Persistent ticket items | Optional |
| xsound | Audio announcements | Optional |
| BigDaddy-Trains | Custom train models and configs | Recommended |

---

*Last Updated: 2026-01-01*
