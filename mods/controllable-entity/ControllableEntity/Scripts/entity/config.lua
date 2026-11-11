-- Copyright © 2026 Jalapeno Labs

-- Every balance and control tunable in one place, so playtests change numbers here and nowhere else.
-- Times are seconds, distances Unreal units (1 unit = 1 cm).

return {
  meter = {
    -- Seconds for the kill meter to fill from empty with nothing happening nearby.
    fillSeconds = 90,
    -- Fill speed multiplier while a noise was heard within `noiseNearbyDistance` in the last few seconds,
    -- so hunting where the crew is rewards the entity faster than hiding.
    noiseNearbyMultiplier = 2.0,
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

  cooldowns = {
    Attack = 1.2,
    Leap = 6,
    Ultimate = 6,
    Vent = 1,
    Peek = 0.5,
    -- The squid's cries on the 1, 2 and 3 keys (cries.lua)
    Roar = 6,
    Curious = 3,
    Call = 6,
  },

  movement = {
    -- The squid moves this much faster in the vents than the game's own crouched speed.
    ventSpeedMultiplier = 1.3,
    -- A full sprint lasts this long, and an empty stamina refills in this long while not sprinting.
    sprintSeconds = 6,
    staminaRefillSeconds = 10,
    -- Out of breath, the squid sprints again once the stamina is back to this fraction.
    staminaToSprintAgain = 0.3,
  },

  attack = {
    -- A basic attack picks the crew member closest to the aim within this reach and cone.
    reach = 350,
    coneDegrees = 60,
  },

  leap = {
    -- The game's own leap lands 300 to 500 units ahead; the entity always leaps this far along their aim.
    distance = 450,
  },

  vents = {
    -- How close across the floor the squid must be to a vent shaft to climb into it from the room below, or to drop
    -- out of it from the duct above.
    enterReach = 400,
    exitReach = 400,
    -- A shaft more than this far above or below doesn't count: it belongs to another floor.
    verticalReach = 900,
    -- How close across the duct floor the squid must be to either end of a step inside the ducts to climb it, and how
    -- far above or below that end it may be. A step rises 250 units, so the two ends never both match.
    climbReach = 250,
    climbVerticalReach = 150,
    -- How close to a floor-level crawl opening's trigger the squid crouches into it, and how fast it must be heading
    -- in (units a second along the opening): the squid is about 176 tall and an opening about 141.
    crawlReach = 120,
    crawlEntrySpeed = 50,
  },

  -- Once a crew member holds the weapon that can kill the specimen (kill and capture contracts), the vents stop being
  -- a hiding place (hunt.lua).
  hunt = {
    -- How long the squid can stay in the vents at a time.
    ventSeconds = 20,
    -- Outside the vents the time refills this many times slower than it drains: a second for every six.
    refillSlowdown = 6,
    -- Once the time has run out, the vents stay shut until it has refilled this far.
    reopenFraction = 0.5,
    -- A squid still in the vents this long after being forced out is moved to the power room.
    stuckSeconds = 10,
    -- The hunted squid cries out this often, so the crew can follow it.
    crySeconds = 12,
  },

  -- Where the entity may not go, and the shuttle's approach (zones.lua).
  zones = {
    -- How far beyond the shuttle's aboard box its approach reaches, across the floor: there the entity can't sprint,
    -- use its ultimate, or kill. Hawking's approach corridor runs about 1,200 units from the airlock.
    shuttleApproach = 1500,
    -- The shortest gap between two "keep out" messages while the player pushes against a forbidden place.
    warningInterval = 3,
  },

  -- The cries the squid makes on its own (cries.lua).
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
    -- The moves that would leave the ducts, which wait until the power is on. Venting decides for itself: dropping
    -- out of the ducts waits, climbing inside them doesn't (abilities.lua).
    heldMoves = { Leap = true, Ultimate = true },
  },

  vision = {
    -- The entity's own light, which only their machine renders: a soft, shadowless glow around the squid, full in the
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
    -- How often the markers follow the squid around.
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
    -- Degrees added to the squid's heading for the player icon: the map draws world +Y up, so yaw 0 (+X) points left.
    iconAngleOffset = -90,
  },

  camera = {
    -- How far the third-person view sits behind the squid.
    thirdPersonDistance = 320,
    -- How far above the squid's centre the camera's arm starts: the first-person eye height.
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
    -- Position blur: a ping lands within this fraction of its distance from the true spot, capped.
    blurFraction = 0.12,
    blurMax = 600,
    -- One footstep ping per walker per this many seconds; footsteps arrive every step.
    footstepInterval = 0.7,
    pingSeconds = 1.5,
    -- Marker size by kind of noise, as a multiple of the 14-pixel marker: gunshots stand out.
    pingScaleByKind = { Gunshot = 2.2, Footstep = 1.0, Alarm = 1.6 },
    -- Noises behind the camera or off the screen sit on a ring around the centre, this fraction of the way to the
    -- nearest screen edge, drawn this much bigger.
    ringRadiusFraction = 0.35,
    ringScale = 1.3,
  },

  keys = {
    -- UE4SS key names for the mod's own keys, which the game binds to nothing. The squid's moves are the game's own
    -- actions instead (control.lua), so the player's own bindings carry over.
    volunteer = "F8",
    -- Host only: turns entity mode on or off for the session.
    entityMode = "F9",
    -- Held to sprint; an Unreal key name (the squid reuses no game action for it: the crew's sprint is bound on the
    -- crew character, not the controller).
    sprint = "LeftShift",
    -- Minimap zoom (UE4SS key names: "." and ",").
    zoomIn = "OEM_PERIOD",
    zoomOut = "OEM_COMMA",
    -- Shows or hides the key hints under the minimap.
    hints = "H",
  },
}
