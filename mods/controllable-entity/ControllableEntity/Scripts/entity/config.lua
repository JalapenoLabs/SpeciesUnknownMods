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
    -- How close to a vent entrance the squid must be to climb in.
    enterReach = 300,
    -- How far from a vent exit the squid can drop out of, measured while inside the duct.
    exitReach = 400,
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
    -- UE4SS key names (the game binds neither).
    ultimate = "SPACE",
    volunteer = "F8",
  },
}
