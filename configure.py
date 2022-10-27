#!/usr/bin/python

import os

# plugin names, relative to `scripting/`
plugins = [
  'addcond_while_active.sp',
  'airblast_projectiles_adds_self_condition.sp',
  'airblast_projectiles_restores_health.sp',
  'alt_fire_throws_cleaver.sp',
  'attr_buff_override.sp',
  'attr_group_overheal_uber.sp',
  'attr_medic_disable_active_regen.sp',
  'attr_nailgun_slow.sp',
  'attr_rage_meter_mult.sp',
  'attr_rage_on_headshot.sp',
  'attr_sapper_recharge_time.sp',
  'attr_sapper_reprograms_buildings.sp',
  'attr_weapon_always_gibs_on_kill.sp',
  'cloak_debuff_time_scale.sp',
  'condition_stack_on_hit.sp',
  'crossbow_addcond_on_teammate_hit.sp',
  'custom_ball_impact_effect.sp',
  'custom_lunchbox_effect.sp',
  'damage_increase_on_hit.sp',
  'disable_sniper_unzoom.sp',
  'disorient_on_hit.sp',
  'energy_ring_impact_effect.sp',
  'energy_ring_instakill_radius.sp',
  'explosive_shield_bash.sp',
  'flamethrower_alt_fire_oil.sp',
  'flare_mods.sp',
  'full_clip_refill_after_time.sp',
  'generate_rage_on_dmg_patch.sp',
  'generate_rage_over_time.sp',
  'jar_is_poison.sp',
  'jar_is_bleed_on_hit.sp',
  'joke_medigun_mod_drain_health.sp',
  'low_gravity_charge.sp',
  'lunchbox_override_pickup_type.sp',
  'minigun_burst_shot_rage.sp',
  'minigun_radial_buff.sp',
  'minigun_rage_projectile_shield.sp',
  'minigun_vacuum.sp',
  'mod_crit_type_on_hitgroup.sp',
  'mod_crit_type_vs_condition.sp',
  'mod_crit_type_vs_sentry_targets.sp',
  'mult_damage_vs_sappers.sp',
  'mult_damage_vs_targetcond.sp',
  'mult_basegrenade_explode_radius.sp',
  'mvm_attributes.sp',
  'override_building_health.sp',
  'owned_building_phasing.sp',
  'preserve_rage.sp',
  'projectile_heal_on_teammate_contact.sp',
  'projectile_override_energy_ball.sp',
  'projectile_upgrades_buildings.sp',
  'pull_target_on_hit.sp',
  'reload_full_clip_at_once.sp',
  'shake_on_step.sp',
  'shake_on_hit.sp',
  'sniper_weapon_rate_aim_target.sp',
  'spontaneous_explode.sp',
  'stack_grenade_damage_custom.sp',
  'syringegun_poison_on_hit.sp',
  'tag_last_enemy_hit.sp',
  'uber_drain_rate_per_extra_player.sp',
  'unsap_metal_cost.sp',
  'weapon_overheat.sp',
  'weapon_rate_buff_ally.sp',
]

plugins += map(lambda p: os.path.join('buff_overrides', p), [
  'buff_control_rockets.sp',
  'buff_crit_and_mark_for_death.sp',
  'buff_enable_tag_players.sp',
  'sniper_rage_buff_reload.sp',
  'sniper_rage_smokeout_spies.sp',
])

plugins += map(lambda p: os.path.join('lunchbox_effects', p), [
  'sugar_frenzy.sp',
  'temp_mod_crit_chance.sp',
])

# files to copy to builddir, relative to root
copy_files = [
	'configs/customweapons/air_lock.cfg',
	'configs/customweapons/apollo_pack.cfg',
	'configs/customweapons/backfill_backslap.cfg',
	'configs/customweapons/banana_blast.cfg',
	'configs/customweapons/bloodhound_5000.cfg',
	'configs/customweapons/bonk_sugar_frenzy.cfg',
	'configs/customweapons/brainteaser.cfg',
	'configs/customweapons/c4shield.cfg',
	'configs/customweapons/chudakov.cfg',
	'configs/customweapons/classic_nailgun.cfg',
	'configs/customweapons/councilman.cfg',
	'configs/customweapons/crop_killer.cfg',
	'configs/customweapons/county_killer.cfg',
	'configs/customweapons/dead_finger.cfg',
	'configs/customweapons/der_schmerzschild.cfg',
	'configs/customweapons/drive_by.cfg',
	'configs/customweapons/essendon_eliminator.cfg',
	'configs/customweapons/enemy_sweeper.cfg',
	'configs/customweapons/f10scorch.cfg',
	'configs/customweapons/garand.cfg',
	'configs/customweapons/harmony_of_repair.cfg',
	'configs/customweapons/homebrew.cfg',
	'configs/customweapons/joke_medick_gun.cfg',
	'configs/customweapons/leidwerfer.cfg',
	'configs/customweapons/magnum_opus.cfg',
	'configs/customweapons/mega_buster.cfg',
	'configs/customweapons/merasmus_stash.cfg',
	'configs/customweapons/moonbeam.cfg',
	'configs/customweapons/plastic_pisstol.cfg',
	'configs/customweapons/primed_directive.cfg',
	'configs/customweapons/public_address.cfg',
	'configs/customweapons/subjugated_saboteur.cfg',
	'configs/customweapons/supply_chain.cfg',
	'configs/customweapons/talos.cfg',
	'configs/customweapons/tank_fists.cfg',
	'configs/customweapons/welder.cfg',
	'configs/customweapons/wunderwaffe.cfg',
	'configs/customweapons/truth_fruit.cfg',
	
	'gamedata/tf2.cattr_starterpack.txt',
	
	'scripting/include/tf_cattr_buff_override.inc',
	'scripting/include/tf_cattr_lunch_effect.inc',
]

include_dirs = [
	'third_party/vendored/',
	'third_party/submodules/',
	'third_party/submodules/smlib/scripting/include/',
]

spcomp_min_version = (1, 10)

########################
# build.ninja script generation below.

import contextlib
import misc.ninja_syntax as ninja_syntax
import misc.spcomp_util
import os
import sys
import argparse
import platform
import shutil

parser = argparse.ArgumentParser('Configures the project.')
parser.add_argument('--spcomp-dir',
		help = 'Directory with the SourcePawn compiler.  Will check PATH if not specified.')

args = parser.parse_args()

print("""Checking for SourcePawn compiler...""")
spcomp = shutil.which('spcomp', path = args.spcomp_dir)
if not spcomp:
	raise FileNotFoundError('Could not find SourcePawn compiler.')

available_version = misc.spcomp_util.extract_version(spcomp)
version_string = '.'.join(map(str, available_version))
print('Found SourcePawn compiler version', version_string, 'at', os.path.abspath(spcomp))

if spcomp_min_version > available_version:
	raise ValueError("Failed to meet required compiler version "
			+ '.'.join(map(str, spcomp_min_version)))

with contextlib.closing(ninja_syntax.Writer(open('build.ninja', 'wt'))) as build:
	build.comment('This file is used to build SourceMod plugins with ninja.')
	build.comment('The file is automatically generated by configure.py')
	build.newline()
	
	vars = {
		'configure_args': sys.argv[1:],
		'root': '.',
		'builddir': 'build',
		'spcomp': spcomp,
		'spcflags': [ '-i${root}/scripting/include', '-h', '-v0' ]
	}
	
	vars['spcflags'] += ('-i{}'.format(d) for d in include_dirs)
	
	for key, value in vars.items():
		build.variable(key, value)
	build.newline()
	
	build.comment("""Regenerate build files if build script changes.""")
	build.rule('configure',
			command = sys.executable + ' ${root}/configure.py ${configure_args}',
			description = 'Reconfiguring build', generator = 1)
	
	build.build('build.ninja', 'configure',
			implicit = [ '${root}/configure.py', '${root}/misc/ninja_syntax.py' ])
	build.newline()
	
	build.rule('spcomp', deps = 'msvc',
			command = '${spcomp} ${in} ${spcflags} -o ${out}',
			description = 'Compiling ${out}')
	build.newline()
	
	# Platform-specific copy instructions
	if platform.system() == "Windows":
		build.rule('copy', command = 'cmd /c copy ${in} ${out} > NUL',
				description = 'Copying ${out}')
	elif platform.system() == "Linux":
		build.rule('copy', command = 'cp ${in} ${out}', description = 'Copying ${out}')
	build.newline()
	
	build.comment("""Compile plugins specified in `plugins` list""")
	for plugin in plugins:
		smx_plugin = os.path.splitext(plugin)[0] + '.smx'
		
		sp_file = os.path.normpath(os.path.join('$root', 'scripting', plugin))
		
		smx_file = os.path.normpath(os.path.join('$builddir', 'plugins', 'custom-attr-starter-pack', smx_plugin))
		build.build(smx_file, 'spcomp', sp_file)
	build.newline()
	
	build.comment("""Copy plugin sources to build output""")
	for plugin in plugins:
		sp_file = os.path.normpath(os.path.join('$root', 'scripting', plugin))
		
		dist_sp = os.path.normpath(os.path.join('$builddir', 'scripting', plugin))
		build.build(dist_sp, 'copy', sp_file)
	build.newline()
	
	build.comment("""Copy other files from source tree""")
	for filepath in copy_files:
		build.build(os.path.normpath(os.path.join('$builddir', filepath)), 'copy',
				os.path.normpath(os.path.join('$root', filepath)))
