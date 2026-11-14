-- Copyright © 2026 Jalapeno Labs

-- Every balance and control tunable the entities share, in one place, so playtests change numbers here. Each entity's
-- own numbers (its moves' cooldowns, reaches and distances) are in its kit (kits/<name>.lua).
-- Times are seconds, distances Unreal units (1 unit = 1 cm).

return {
  meter = {
    -- Seconds for the kill meter to fill from empty with nothing happening nearby (playtest 9: 90, with the noise
    -- bonus at twice, filled it in under a minute of hunting, far too fast).
    fillSeconds = 180,
    -- Fill speed multiplier while a noise was heard within `noiseNearbyDistance` in the last few seconds,
    -- so hunting where the crew is rewards the entity faster than hiding.
    noiseNearbyMultiplier = 1.5,
    -- How much of the meter a hit that lands on a crew member adds, so the kill is earned by hunting: at most once
    -- per crew member every `hitChargeSeconds`, since one swing can hit several times. A hit on a shield isn't one.
    hitCharge = 0.1,
    hitChargeSeconds = 1,
    noiseNearbyDistance = 1500,
    noiseNearbyMemory = 3,
    -- Fill speed multiplier during partial frenzy (kill and capture contracts, once a crew member has the special
    -- weapon).
    partialFrenzyMultiplier = 2.5,
    -- After pressing the ultimate, how long the guaranteed kill stays armed waiting for a grab to land.
    armedWindow = 3,
    -- In full frenzy kills cost no meter, but each kill re-arms only after this delay.
    frenzyRearm = 7,
  },

  -- The commands every entity shares; its four slots' cooldowns are its kit's.
  cooldowns = {
    Peek = 0.5,
    -- The entity's cries on the 1, 2 and 3 keys (cries.lua)
    Roar = 6,
    Curious = 3,
    Call = 6,
  },

  movement = {
    -- The entity moves this much faster in the vents than the game's own crouched speed (playtest 9: 1.3 was too slow
    -- to get anywhere in time; 60% faster than that).
    ventSpeedMultiplier = 2.1,
    -- A full sprint lasts this long, and an empty stamina refills in this long while not sprinting (playtest 9: 6 and
    -- 10 left the entity no chance of catching the crew).
    sprintSeconds = 9,
    staminaRefillSeconds = 3.3,
    -- Out of breath, the entity sprints again once the stamina is back to this fraction.
    staminaToSprintAgain = 0.3,
  },

  vents = {
    -- How close across the floor the entity must be to a vent shaft to climb into it from the room below, or to drop
    -- out of it from the duct above.
    enterReach = 400,
    exitReach = 400,
    -- A shaft more than this far above or below doesn't count: it belongs to another floor.
    verticalReach = 900,
    -- How close across the duct floor the entity must be to either end of a step inside the ducts to climb it, and how
    -- far above or below that end it may be. A step rises 250 units, so the two ends never both match.
    climbReach = 250,
    climbVerticalReach = 150,
    -- How far across the duct floor the entity may crawl from where it started peeking before the peek ends.
    peekBreakDistance = 80,
    -- How close to a floor-level crawl opening's trigger the entity crouches into it, and how fast it must be heading
    -- in (units a second along the opening): the squid is about 176 tall and an opening about 141.
    crawlReach = 120,
    crawlEntrySpeed = 50,
  },

  -- The entity's flight (flee.lua): once the squid has an eye broken (Mike, a face) and is back up, it runs at its top
  -- speed with a full sprint for this long, as the AI escapes. An eye broken without the game's escape this long after
  -- gets the game's own ink get-up, which ends in it.
  flee = {
    seconds = 20,
    escapeWaitSeconds = 12,
  },

  -- The entity's fear (fear.lua): the health bar's share under which its heart starts racing (as the crew's below 30%
  -- health), at a quarter's fear, and the share at which it races fastest; the heat at which the squid counts as
  -- burning and the fear that brings; how near a crew member must be, once the crew holds the weapon that can kill it,
  -- for it to feel hunted, and that fear. A drop of hitShare in the health bar between two frames is a hit (a red
  -- flash), of hardHitShare a hard one (the blur). The heartbeat's volume at the least fear, and its pitch from the
  -- least fear to the most (the crew's: 0.85 to 1.2).
  fear = {
    lowHealthShare = 0.3,
    lowestHealthShare = 0.1,
    lowHealthFear = 0.25,
    burningHeat = 0.25,
    burningFear = 0.8,
    huntedDistance = 1500,
    huntedFear = 0.5,
    hitShare = 0.02,
    hardHitShare = 0.25,
    quietestBeat = 0.5,
    lowestPitch = 0.85,
    highestPitch = 1.2,
  },

  hud = {
    -- How long a word in the huge red banner stays up (RUN, as the flight starts); it fades over its last second.
    bannerSeconds = 3,
  },

  -- Once a crew member holds the weapon that can kill the specimen (kill and capture contracts), the vents stop being
  -- a hiding place (hunt.lua).
  hunt = {
    -- How long the entity can stay in the vents at a time.
    ventSeconds = 20,
    -- Outside the vents the time refills this many times slower than it drains: a second for every six.
    refillSlowdown = 6,
    -- Once the time has run out, the vents stay shut until it has refilled this far.
    reopenFraction = 0.5,
    -- An entity still in the vents this long after being forced out is moved to the power room.
    stuckSeconds = 10,
    -- The hunted entity cries out this often, so the crew can follow it.
    crySeconds = 12,
  },

  -- Where the entity may not go, and the shuttle's approach (zones.lua).
  zones = {
    -- How far beyond the shuttle's aboard box its approach reaches, across the floor: there the entity can't sprint,
    -- use its ultimate, or kill. Hawking's approach corridor runs about 1,200 units from the airlock.
    shuttleApproach = 1500,
    -- The shortest gap between two "keep out" messages while the player pushes against a forbidden place.
    warningInterval = 3,
    -- How far beyond an elevator car's trigger box the entity is kept: its capsule (radius 50) must never touch the
    -- box, even sprinting for the fifth of a second between checks, or the elevator refuses to start (zones.lua).
    elevatorMargin = 150,
  },

  -- The areas of the ship the entity stands in (areas.lua).
  areas = {
    -- How much higher than its top a map section's volume reaches for the entity: the ducts over the labs climb past
    -- the volumes, which only reach as high as the crew can climb (playtest 9).
    sectionHeadroom = 1500,
    -- How often the entity's machine looks for the actors whose areas it follows: each lookup walks every object in
    -- the game, and some (the lab's jars, the morays) appear mid-mission.
    rescanSeconds = 2,
  },

  -- The cries the entity makes on its own (cries.lua).
  cries = {
    -- The "seen you" call: when the entity first sees a crew member within this range and view cone (degrees, all
    -- the way across), at most this often.
    sightRange = 3000,
    sightConeDegrees = 90,
    seenCallSeconds = 8,
  },

  lair = {
    -- The entity starts in the vent nearest the game's spawn point that is at least this far from every crew member
    -- (the vent farthest from them when none is).
    minimumCrewDistance = 2500,
    -- The shortest gap between two "the vents hold you" messages while the player tries to leave the ducts.
    warningInterval = 3,
  },

  vision = {
    -- The entity's own light, which only their machine renders: a soft, shadowless glow around the entity, full in the
    -- unlit ducts and faint in the rooms, which the game keeps dark on purpose (the crew are meant to need
    -- flashlights).
    lanternCandelas = 80,
    lanternRadius = 1500,
    roomLanternCandelas = 20,
    roomLanternRadius = 900,
    lanternColor = { R = 0.78, G = 0.88, B = 1.0, A = 1 },
    -- Glowing markers at the vent openings within this distance (only the entity sees them), at most this many.
    markerRange = 3500,
    markerCount = 16,
    -- Above 1, the unlit colour blooms, so the markers read as glowing.
    markerColor = { R = 0.25, G = 1.4, B = 3.0, A = 1 },
    -- Marker disc size, as the scale of the engine's 1 m cylinder.
    markerScale = { X = 0.8, Y = 0.8, Z = 0.03 },
    -- How often the markers follow the entity around.
    markerRefreshSeconds = 0.5,
    -- The posts around the places the entity may not go (red) and the shuttle's approach (amber), one every this
    -- many units along each edge, this thick as the engine cylinder's scale. Rebuilt this often if the places changed
    -- (a forbidden area streams in with its section).
    postSpacing = 400,
    postThickness = 0.12,
    forbiddenColor = { R = 3.0, G = 0.12, B = 0.08, A = 1 },
    approachColor = { R = 3.0, G = 1.1, B = 0.08, A = 1 },
    zoneRefreshSeconds = 2,
  },

  minimap = {
    -- The square's side and its distance from the screen's top-right corner, in HUD units (1080p pixels).
    size = 300,
    margin = 24,
    -- The game's minimap Scale: larger zooms in. At 1 the whole ship fits the square; the crew's tool, on a 1024-pixel
    -- screen, runs from 0.7 to 1.0. The minimap always starts fully zoomed out.
    minimumZoom = 1.0,
    maximumZoom = 8.0,
    zoomStep = 1.25,
    -- Degrees added to the entity's heading for the player icon: the map draws world +Y up, so yaw 0 (+X) points left.
    iconAngleOffset = -90,
  },

  camera = {
    -- How far the third-person view sits behind the entity.
    thirdPersonDistance = 320,
    -- How far above the entity's centre the camera's arm starts: the first-person eye height.
    height = 70,
    -- How far down the player can look in third person, in degrees below level. Further down, the arm swings the camera
    -- up through the ship's outer hull in places (playtest 6). First person keeps the game's own limit.
    thirdPersonLowestPitch = -50,
  },

  look = {
    -- Matches the crew character's own look scale (BP_Character.BPI_PlayerInput_Look).
    sensitivity = 1.0,
  },

  senses = {
    -- The AI monster's hearing range (BP_Basic_AI_Controller's hearing sense, 4000 units); a noise is heard when
    -- it is within this range times its loudness and within the noise's own range.
    hearingRange = 4000,
    -- One footstep ping per walker per this many seconds; footsteps arrive every step.
    footstepInterval = 0.7,
    -- How long a marker fades over, for a noise whose source the entity's machine can't show (silhouettes.lua).
    pingSeconds = 1.5,
    -- How often an overloading engine is pinged, at any distance, while the overload lasts.
    overloadPingSeconds = 1,
    -- Marker size by kind of noise, as a multiple of the 20-pixel pulse ring: gunshots stand out.
    pingScaleByKind = { Gunshot = 2.2, Footstep = 1.0, Alarm = 1.6, Overload = 1.6, Sense = 1.8 },
    -- With nothing heard for this long, the entity senses every living crew member: a pink ping each, blurred within
    -- this fraction of its distance, capped, so it gives a direction and a rough distance, never a position
    -- (playtest 9: lost in the vents with nothing to go on, the entity "may as well have lost the game").
    senseSeconds = 15,
    senseBlurFraction = 0.3,
    senseBlurMax = 2500,
    -- Noises behind the camera or off the screen sit on a ring around the centre, this fraction of the way to the
    -- nearest screen edge, drawn this much bigger.
    ringRadiusFraction = 0.35,
    ringScale = 1.3,
  },

  -- What the entity hears, seen through walls (silhouettes.lua): the outline's colour and thickness, how each kind of
  -- noise shows (its brightness, how long after the last news of it, and whether it pulses meanwhile), how fast the
  -- pulse goes, and how often the crew are kept out of the outline.
  silhouettes = {
    color = { R = 1.0, G = 0.08, B = 0.05, A = 1 },
    thickness = 2.5,
    pulseSeconds = 1.0,
    crewSweepSeconds = 0.5,
    byKind = {
      Gunshot = { strength = 1.0, seconds = 1.5 },
      Footstep = { strength = 0.35, seconds = 0.6 },
      -- A door's alarm beats every half second, an overload is told every second: each lasts a little longer
      Alarm = { strength = 1.0, seconds = 1.0, pulses = true },
      Overload = { strength = 1.0, seconds = 1.5, pulses = true },
    },
  },

  keys = {
    -- UE4SS key names for the mod's own keys, which the game binds to nothing. The entity's moves are the game's own
    -- actions instead (control.lua), so the player's own bindings carry over.
    volunteer = "F8",
    -- Host only, in the lobby: opens the entity picker (picker.lua), and closes it.
    picker = "F9",
    -- Held to sprint; an Unreal key name (the entity reuses no game action for it: the crew's sprint is bound on the
    -- crew character, not the controller).
    sprint = "LeftShift",
    -- Minimap zoom (UE4SS key names: "." and ",").
    zoomIn = "OEM_PERIOD",
    zoomOut = "OEM_COMMA",
    -- Shows or hides the key hints under the minimap.
    hints = "H",
    -- Held to get the entity unstuck (unstuck.lua).
    unstuck = "F7",
  },

  -- The entity's unstuck (unstuck.lua): how long the key is held, how far the entity may drift meanwhile, and how long
  -- before it works again.
  unstuck = {
    holdSeconds = 5,
    stillDistance = 100,
    cooldownSeconds = 120,
  },
}
