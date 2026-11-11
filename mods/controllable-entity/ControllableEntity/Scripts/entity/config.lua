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
  },

  lair = {
    -- The entity starts inside a vent at least this far from every crew member (the farthest one when none is).
    minimumCrewDistance = 2500,
    -- Until the crew turns the power on, the squid stays inside the ducts within this distance of its start.
    leashRadius = 1200,
    -- The shortest gap between two "the vents hold you" messages while the player pushes against the leash.
    warningInterval = 3,
    -- The moves that would leave the ducts, which wait until the power is on.
    heldMoves = { Leap = true, Vent = true, Ultimate = true },
  },

  vision = {
    -- The entity's own light, which only their machine renders: a soft, shadowless glow around the squid.
    lanternCandelas = 80,
    lanternRadius = 1500,
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
  },

  camera = {
    -- How far the third-person view sits behind the squid.
    thirdPersonDistance = 320,
    -- How far above the squid's centre the camera's arm starts: the first-person eye height.
    height = 70,
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
  },

  keys = {
    -- UE4SS key names (the game binds none of them).
    ultimate = "SPACE",
    volunteer = "F8",
    -- Host only: turns entity mode on or off for the session.
    entityMode = "F9",
  },
}
