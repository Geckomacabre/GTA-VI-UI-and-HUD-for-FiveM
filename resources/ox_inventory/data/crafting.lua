local crafting = {
	{
		name = 'advanced_weapon_bench',
		items = {
			{
				name = 'WEAPON_MINISMG',
				ingredients = {
					['toolkit'] = 1,
					['scrapmetal'] = 10,
					['metalparts'] = 25,
				},
				duration = 10000,
				count = 1,
			},
			{
				name = 'WEAPON_ASSAULTRIFLE',
				ingredients = {
					['steel'] = 15,
					['metalparts'] = 35,
					['toolkit'] = 2,
				},
				duration = 15000,
				count = 1,
			},
			{
				name = 'ammo-9',
				ingredients = {
					['shell_casing'] = 12,
					['gunpowder'] = 6,
					['metalparts'] = 3,
				},
				duration = 4000,
				count = 30,
			},
			{
				name = 'ammo-rifle2',
				ingredients = {
					['shell_casing'] = 20,
					['gunpowder'] = 10,
					['metalparts'] = 5,
				},
				duration = 5000,
				count = 30,
			},
			{
				name = 'shell_casing',
				ingredients = {
					['ammo-9'] = 10,
				},
				duration = 3000,
				count = 12,
			},
		},
		points = {
			vec3(3.3153, -1482.429932, 31.846201),
		},
		zones = {
			{
				icon = 'fa-solid fa-wrench',
				coords = vec3(3.3153, -1482.429932, 31.846201),
				size = vec3(1.8, 1.8, 1.8),
				distance = 2,
				rotation = 139.7875,
			},
		},
	},
	{
		name = 'fabrication_bench',
		groups = {
			['welder'] = 0,
			['mechanic'] = 0,
		},
		items = {
			{
				name = 'repairitem',
				ingredients = {
					['steel'] = 3,
					['metalparts'] = 5,
					['toolkit'] = 1,
				},
				duration = 10000,
				count = 1,
			},
			{
				name = 'toolkit',
				ingredients = {
					['rubber'] = 2,
					['steel'] = 4,
					['metalparts'] = 8,
				},
				duration = 12000,
				count = 1,
			},
			{
				name = 'metalparts',
				ingredients = {
					['scrapmetal'] = 5,
					['steel'] = 2,
				},
				duration = 6000,
				count = 3,
			},
			{
				name = 'paint_can',
				ingredients = {
					['plastic'] = 2,
					['copper'] = 1,
					['aluminum'] = 3,
				},
				duration = 7000,
				count = 2,
			},
			{
				name = 'paint_thinner',
				ingredients = {
					['glass_scrap'] = 1,
					['plastic'] = 2,
				},
				duration = 5000,
				count = 2,
			},
			{
				name = 'shop_rag',
				ingredients = {
					['plastic'] = 1,
				},
				duration = 2000,
				count = 5,
			},
		},
		points = {
			vec3(1765.272583, 3332.584229, 40.438599),
			vec3(1146.345581, -778.157288, 56.598701),
			vec3(541.383789, -180.637299, 53.4813),
		},
	},
	{
		name = 'kitchen_bench',
		items = {
			{
				name = 'burger',
				ingredients = {
					['lettuce'] = 1,
					['meat'] = 1,
					['burgerbuns'] = 1,
				},
				duration = 4000,
				count = 1,
			},
			{
				name = 'steak_and_eggs',
				ingredients = {
					['cooking_oil'] = 1,
					['meat'] = 2,
					['eggs'] = 2,
				},
				duration = 6000,
				count = 1,
			},
			{
				name = 'chicken_and_waffles',
				ingredients = {
					['cooking_oil'] = 1,
					['chicken_fillet'] = 1,
					['flour'] = 2,
					['eggs'] = 1,
				},
				duration = 6000,
				count = 1,
			},
			{
				name = 'fish_and_chips',
				ingredients = {
					['flour'] = 1,
					['fish_fillet'] = 1,
					['potato'] = 2,
					['cooking_oil'] = 1,
				},
				duration = 5500,
				count = 1,
			},
			{
				name = 'cheese_fries',
				ingredients = {
					['cooking_oil'] = 1,
					['potato'] = 2,
					['cheese'] = 1,
				},
				duration = 4000,
				count = 1,
			},
			{
				name = 'nachos',
				ingredients = {
					['cheese'] = 2,
					['tortilla'] = 2,
				},
				duration = 4000,
				count = 1,
			},
			{
				name = 'barbacoa_taco',
				ingredients = {
					['tortilla'] = 1,
					['meat'] = 1,
					['tomato'] = 1,
				},
				duration = 3500,
				count = 2,
			},
			{
				name = 'vanilla_milkshake',
				ingredients = {
					['vanilla_extract'] = 1,
					['milk'] = 2,
				},
				duration = 3000,
				count = 1,
			},
			{
				name = 'chocolate_milkshake',
				ingredients = {
					['chocolate_syrup'] = 1,
					['milk'] = 2,
				},
				duration = 3000,
				count = 1,
			},
			{
				name = 'strawberry_milkshake',
				ingredients = {
					['milk'] = 2,
					['strawberries'] = 2,
				},
				duration = 3000,
				count = 1,
			},
			{
				name = 'ice_cream',
				ingredients = {
					['vanilla_extract'] = 1,
					['strawberries'] = 1,
					['milk'] = 2,
				},
				duration = 4000,
				count = 2,
			},
		},
		points = {
			vec3(1587.599976, 6455.299805, 25),
			vec3(2556.399902, 385, 108.599998),
		},
	},
	{
		name = 'lockpick_crafting',
		items = {
			{
				name = 'lockpick',
				ingredients = {
					['scrapmetal'] = 5,
					['WEAPON_HAMMER'] = 1,
				},
				duration = 5000,
				count = 2,
			},
		},
		points = {
			vec3(-1147.079956, -2002.660034, 13.18),
		},
		zones = {
			{
				icon = 'fa-solid fa-wrench',
				coords = vec3(-1146.199951, -2002.050049, 13.2),
				size = vec3(3.8, 1.05, 0.15),
				distance = 1.5,
				rotation = 315,
			},
		},
	},
	{
		name = 'meth_lab_kit_bench',
		items = {
			{
				name = 'kq_meth_lab_kit',
				ingredients = {
					['glass_scrap'] = 3,
					['steel'] = 5,
					['circuit_board'] = 2,
					['plastic'] = 10,
				},
				duration = 12000,
				count = 1,
			},
		},
		points = {
			vec3(1389.923584, 3605.918945, 38.777901),
		},
		zones = {
			{
				icon = 'fa-solid fa-wrench',
				coords = vec3(1389.923584, 3605.918945, 38.777901),
				size = vec3(1, 1, 1),
				distance = 1.5,
				rotation = 180,
			},
		},
	},
	{
		name = 'rifle_ammo_bench',
		items = {
			{
				name = 'WEAPON_CARBINERIFLE_MK2',
				ingredients = {
					['plastic'] = 10,
					['steel'] = 25,
					['circuit_board'] = 2,
					['aluminum'] = 15,
				},
				duration = 15000,
				count = 1,
			},
			{
				name = 'WEAPON_SNSPISTOL',
				ingredients = {
					['steel'] = 10,
					['plastic'] = 4,
					['aluminum'] = 5,
				},
				duration = 10000,
				count = 1,
			},
			{
				name = 'ammo-rifle',
				ingredients = {
					['shell_casing'] = 5,
					['gunpowder'] = 5,
					['metalparts'] = 3,
				},
				duration = 8000,
				count = 1,
			},
			{
				name = 'ammo-45',
				ingredients = {
					['shell_casing'] = 3,
					['gunpowder'] = 3,
					['metalparts'] = 2,
				},
				duration = 7000,
				count = 1,
			},
			{
				name = 'shell_casing',
				ingredients = {
					['ammo-9'] = 1,
				},
				duration = 4000,
				count = 3,
			},
		},
		points = {
			vec3(411.623291, -1492.77356, 33.668598),
		},
		zones = {
			{
				icon = 'fa-solid fa-wrench',
				coords = vec3(411.623291, -1492.77356, 33.668598),
				size = vec3(1, 1, 1),
				distance = 1.5,
				rotation = 210.1507,
			},
		},
	},
	{
		name = 'smokehouse_bench',
		items = {
			{
				name = 'deer_jerky',
				ingredients = {
					['meath'] = 2,
				},
				duration = 8000,
				count = 3,
			},
			{
				name = 'trail_mix',
				ingredients = {
					['corn'] = 2,
					['strawberries'] = 1,
				},
				duration = 5000,
				count = 2,
			},
			{
				name = 'meat',
				ingredients = {
					['meath'] = 1,
					['WEAPON_KNIFE'] = 1,
				},
				duration = 5000,
				count = 2,
			},
			{
				name = 'fish_fillet',
				ingredients = {
					['fish'] = 1,
					['WEAPON_KNIFE'] = 1,
				},
				duration = 4000,
				count = 2,
			},
		},
		points = {
			vec3(-66.800003, 6237.959961, 31.09),
		},
	},
	{
		name = 'tackle_bench',
		items = {
			{
				name = 'fishingrod',
				ingredients = {
					['rubber'] = 2,
					['wood'] = 3,
					['metalparts'] = 1,
				},
				duration = 8000,
				count = 1,
			},
			{
				name = 'fishing_reel',
				ingredients = {
					['rubber'] = 1,
					['metalparts'] = 3,
					['plastic'] = 2,
				},
				duration = 7000,
				count = 1,
			},
			{
				name = 'artificial_bait',
				ingredients = {
					['rubber'] = 1,
					['plastic'] = 1,
				},
				duration = 3000,
				count = 5,
			},
			{
				name = 'graphite_rod',
				ingredients = {
					['rubber'] = 2,
					['carbon'] = 5,
					['fishingrod'] = 1,
				},
				duration = 12000,
				count = 1,
			},
		},
		points = {
			vec3(-674.498718, 5835.202637, 16.3314),
		},
	},
	{
		name = 'thermite_bench',
		items = {
			{
				name = 'thermite',
				ingredients = {
					['iron'] = 5,
					['toolkit'] = 1,
					['aluminum'] = 10,
				},
				duration = 10000,
				count = 3,
			},
		},
		points = {
			vec3(2431.240234, 4970.818848, 42.347599),
		},
		zones = {
			{
				icon = 'fa-solid fa-wrench',
				coords = vec3(2431.240234, 4970.818848, 42.347599),
				size = vec3(3.5, 3.5, 3.5),
				distance = 1.5,
				rotation = 0,
			},
		},
	},
	{
		name = 'weapon_bench',
		items = {
			{
				name = 'ammo-9',
				ingredients = {
					['shell_casing'] = 10,
					['gunpowder'] = 5,
				},
				duration = 4000,
				count = 10,
			},
			{
				name = 'WEAPON_TECPISTOL',
				ingredients = {
					['metalparts'] = 15,
					['toolkit'] = 1,
				},
				duration = 8000,
				count = 1,
			},
		},
		points = {
			vec3(80.387199, -1958.763794, 21.123199),
		},
		zones = {
			{
				icon = 'fa-solid fa-wrench',
				coords = vec3(80.387199, -1958.763794, 21.123199),
				size = vec3(3.5, 1.5, 0.2),
				distance = 1.5,
				rotation = 45.8141,
			},
		},
	},
}

return crafting
