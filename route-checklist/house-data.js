// House-specific data for the Route Checklist.
//
// Each house entry:
//   name      — house name shown in the sidebar picker (must be unique)
//   equipment — flags for gear the house may or may not have.
//               false  = house does NOT have it → related checklist items hide.
//               true / missing = shown as normal.
//               Flags used: generator, roofCoils, sumpPump, garbageDisposal,
//                           frontLoadWashers, airExchanger, waterSoftener
//   notes     — house-specific detail shown inline under the matching
//               checklist item. Keys: fireExtinguishers, furnaceFilter,
//               fridgeCoils, waterSoftener, shutoffs, knives, medLock,
//               atticAccess, dryerVents
//   info      — [label, detail] pairs with no checklist item; shown in the
//               sidebar "House info" panel.
//
// Door/entry codes are NOT stored here — they live in house-codes.local.js,
// which stays on the device and is never committed (see .gitignore).
const HOUSES = [
  {
    name: "Dogwood",
    equipment: {
      roofCoils: true,
      airExchanger: true,
      frontLoadWashers: false,
    },
    notes: {
      fireExtinguishers: "Up: laundry closet · Down: mech room · Garage: by main door · One in the van",
      furnaceFilter: "20x25x20",
      fridgeCoils: "Upstairs: front · Downstairs: back",
      waterSoftener: "In the mechanical room",
      shutoffs: "Gas & water: mech room. Outside water: mech room above softener + under RS kitchen sink",
      knives: "Block on counter",
      medLock: "Stelth 2256",
      atticAccess: "Attic access: hallway by bathroom",
      dryerVents: "Upstairs: NW side · Downstairs: NE side under deck",
    },
    info: [
      ["Paint", "Laundry closet"],
      ["Fuse box", "Garage by MTX cabinet"],
      ["Med lock", "Stelth 2256"],
      ["Attic access", "Hallway by bathroom"],
    ],
  },
  {
    name: "Roselawn",
    equipment: {
      generator: true,
      waterSoftener: true,
      sumpPump: false,
      roofCoils: false,
      garbageDisposal: false,
      frontLoadWashers: false,
    },
    notes: {
      fireExtinguishers: "Up: kitchen sink, van, garage · Downstairs: kitchen sink",
      furnaceFilter: "16x25x1 — change monthly",
      shutoffs: "Main water: mech room by washing machine. Main gas: mech room by furnace. Outside: behind back-yard faucet in wall + mech room above softener",
      medLock: "Magnet and key",
      atticAccess: "Attic access: big closet in dining area",
    },
    info: [
      ["Paint", "Storage room by RS kitchen"],
      ["MTX cabinet", "Garage"],
      ["Jacuzzi tub cover", "Velcro"],
      ["Humidifier", "Mech room"],
      ["Med lock", "Magnet and key"],
      ["Attic access", "Big closet in dining area"],
    ],
  },
];
