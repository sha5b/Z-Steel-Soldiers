class_name Groups
extends Object
## Scene-tree group names — one spelling, greppable. A typo'd group
## string fails SILENTLY (the repair bay sat unreachable because scans
## used a group it was never in), so every add/remove/query goes
## through these constants. Add new groups here first.

const UNITS := "units"                  # every live unit (robots, vehicles, cannons)
const SELECTABLE := "selectable"        # player-clickable entities
const BUILDINGS := "buildings"          # FORTS only (legacy name — do not widen)
const ALL_BUILDINGS := "all_buildings"  # forts + factories + radar + repair + bridges
const FACILITIES := "facilities"        # producers + forts (quick bar, tech ladder)
const ROCKS := "rocks"                  # clearable map rocks
const PICKUPS := "pickups"              # crates
const ANIMALS := "animals"              # ambient critters
const PARADE := "parade"                # victory celebration walkers
const TRACKS := "tracks"                # ground track decals
const CRATERS := "craters"              # blast craters
