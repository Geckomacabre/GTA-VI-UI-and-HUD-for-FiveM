return {
	-- 0	vehicle has no storage
	-- 1	vehicle has no trunk storage
	-- 2	vehicle has no glovebox storage
	-- 3	vehicle has trunk in the hood
	Storage = {
		[`jester`] = 3,
		[`adder`] = 3,
		[`osiris`] = 1,
		[`pfister811`] = 1,
		[`penetrator`] = 1,
		[`autarch`] = 1,
		[`bullet`] = 1,
		[`cheetah`] = 1,
		[`cyclone`] = 1,
		[`voltic`] = 1,
		[`reaper`] = 3,
		[`entityxf`] = 1,
		[`t20`] = 1,
		[`taipan`] = 1,
		[`tezeract`] = 1,
		[`torero`] = 3,
		[`turismor`] = 1,
		[`fmj`] = 1,
		[`infernus`] = 1,
		[`italigtb`] = 3,
		[`italigtb2`] = 3,
		[`nero2`] = 1,
		[`vacca`] = 3,
		[`vagner`] = 1,
		[`visione`] = 1,
		[`prototipo`] = 1,
		[`zentorno`] = 1,
		[`trophytruck`] = 0,
		[`trophytruck2`] = 0,
	},

	-- slots, maxWeight; default weight is 8000 per slot
	glovebox = {
		[0] = {10, 10000},		-- Compact
		[1] = {10, 10000},		-- Sedan
		[2] = {10, 10000},		-- SUV
		[3] = {10, 10000},		-- Coupe
		[4] = {10, 10000},		-- Muscle
		[5] = {10, 18000},		-- Sports Classic
		[6] = {10, 10000},		-- Sports
		[7] = {10, 10000},		-- Super
		[8] = {8, 8000},		-- Motorcycle
		[9] = {10, 10000},		-- Offroad
		[10] = {10, 10000},		-- Industrial
		[11] = {10, 10000},		-- Utility
		[12] = {10, 10000},		-- Van
		[14] = {10, 10000},	-- Boat
		[15] = {20, 24000},	-- Helicopter
		[16] = {40, 40000},	-- Plane
		[17] = {10, 10000},		-- Service
		[18] = {10, 10000},		-- Emergency
		[19] = {10, 10000},		-- Military
		[20] = {10, 10000},		-- Commercial (trucks)
		models = {
			[`xa21`] = {11, 88000}
		}
	},

	trunk = {
		[0] = {50, 40000},		-- Compact
		[1] = {50, 40000},		-- Sedan
		[2] = {50, 40000},		-- SUV
		[3] = {50, 40000},		-- Coupe
		[4] = {50, 40000},		-- Muscle
		[5] = {50, 40000},		-- Sports Classic
		[6] = {50, 40000},		-- Sports
		[7] = {50, 40000},		-- Super
		[8] = {20, 20000},		-- Motorcycle
		[9] = {50, 80000},		-- Offroad
		[10] = {50, 100000},	-- Industrial
		[11] = {40, 100000},	-- Utility
		[12] = {60, 100000},	-- Van
		-- [14] -- Boat
		-- [15] -- Helicopter
		-- [16] -- Plane
		[17] = {40, 40000},	-- Service
		[18] = {40, 40000},	-- Emergency
		[19] = {40, 40000},	-- Military
		[20] = {60, 100000},	-- Commercial
		models = {
			[`xa21`] = {11, 10000}
		},
	}
}
