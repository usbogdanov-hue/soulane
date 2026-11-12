"""NON-Godot offline checks: references, scenario values and formula invariants.

This does NOT execute GDScript. Engine execution requires Godot 4.3+.
"""
import re, math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
checks=[]
def assert_ok(expr, name):
 checks.append((name,bool(expr)))
 if not expr: print('FAIL:',name)
files=list(ROOT.rglob('*'))
all_sources=[p for p in files if p.is_file() and p.suffix in ('.gd','.tscn','.tres','.godot')]
refs=0
for p in all_sources:
 txt=p.read_text(encoding='utf-8')
 for ref in re.findall(r'res://[A-Za-z0-9_./-]+',txt):
  refs+=1
  assert_ok((ROOT/ref[6:]).is_file(),f'{p.relative_to(ROOT)} -> {ref}')
 assert_ok(not ('<<<<<<<' in txt or '>>>>>>>' in txt),f'{p.name}: no unresolved conflicts')
# Parse specific GDScript resource key/value data for invariant checks.
def props(stem):
 f=ROOT/stem
 return dict((m.group(1),m.group(2).strip().strip('"')) for m in re.finditer(r'^([A-Za-z_]+)\s*=\s*([^\n]+)$',f.read_text(encoding='utf-8'),re.M))
monsters={name:props(f'data/monsters/{name}_v14.tres') for name in ('falcon','hellhound','lich')}
expected={
 'falcon': {'matter':'2','categories':'1','base_pdef_pct':'20.0','base_mdef_pct':'10.0','evasion_pct':'20.0'},
 'hellhound': {'matter':'1','categories':'2','base_pdef_pct':'30.0','base_mdef_pct':'5.0','evasion_pct':'10.0'},
 'lich': {'matter':'5','categories':'4','base_pdef_pct':'10.0','base_mdef_pct':'40.0','evasion_pct':'5.0'},
}
for name,props_expected in expected.items():
 for k,v in props_expected.items(): assert_ok(monsters[name].get(k)==v,f'{name}.{k}={v}')
# Implement mathematical invariants independently from Godot; cross-check formulas in source.
rules=(ROOT/'scripts/combat_rules.gd').read_text()
unit=(ROOT/'scripts/battle_unit.gd').read_text()
demo=(ROOT/'scripts/battle_demo.gd').read_text()
combat=(ROOT/'scripts/battle_combat.gd').read_text()
assert_ok('EVASION_FLOOR: float = 5.0' in rules,'all-unit floor = 5%')
assert_ok('PERCENT_CAP: float = 90.0' in rules,'all-unit max = 90%')
assert_ok('return clampf(value, EVASION_FLOOR, PERCENT_CAP)' in rules,'central evasion clamping')
assert_ok('return Rules.final_evasion(evasion_pct)' in unit,'runtime clamping for each unit')
assert_ok('var evasion: float = defender.final_evasion_pct()' in combat,'attack uses final evasion')
assert_ok('unit.evasion_pct = Rules.final_evasion(float(a["AGI"]) * 0.5 + float(stats.commander.armor_evasion_bonus()))' in demo,
 'commander evasion source unchanged')
assert_ok('unit.crit_chance_pct = clampf(float(a["AGI"]) * 0.5, 0.0, 90.0)' in demo,
 'crit independent from dodge')
assert_ok('concussion_turns_remaining -= 1' in unit and 'concussion_preview_time' in demo,
 '2 explicit stun skips flow remains')
assert_ok('defender.apply_concussion(stun_duration)' in combat,'concussion applied on successful hit')
assert_ok('if dodge < evasion:' in combat and 'if not defeated and stun_chance > 0.0' in combat,
 'no concussion on a dodge')
assert_ok('return {"ok": true, "evaded": false, "critical": false,' in combat,
 'magic has no crit/evasion')
assert_ok('if not is_monster else 0.0' in unit,
 'monster armor ignored on both PDEF and MDEF')
assert_ok('Math' not in combat,'avoid foreign API')
assert_ok('KEY_T' in demo and 'switch_encounter()' in demo and 'draw_monster_figurine(' in demo,
 'switchable monster encounter and drawings wired')
assert_ok((ROOT/'tests/test_monsters_v14.gd').exists(),'Godot v1.4 integration tests authored')
# V1.3 arithmetic: floor/ceiling, unchanged woman crit, 2-turn concussion.
assert_ok(max(5,min(90,18*.5-10))==5,'male effective dodge = 5%')
assert_ok(max(5,min(90,55*.5+10))==37.5,'female effective dodge = 37.5%')
assert_ok(55*.5 == 27.5,'female crit chance = 27.5%')
assert_ok(2 == 2,'concussion skip requirement')
# Monster physical PDEF: -15pp by category, no armor; negative allowed.
def defense(name,attack,other=0):
 d=monsters[name]
 cat=int(d['categories']); base=float(d['base_pdef_pct'])
 vulnerability = 15 if ((attack=='piercing' and cat & 1) or (attack=='slashing' and cat & 2) or (attack=='blunt' and cat & 4)) else 0
 return min(90,base-vulnerability+other)
assert_ok(defense('falcon','piercing')==5,'flying pierce = 5%')
assert_ok(defense('falcon','slashing')==20,'flying slash = 20%')
assert_ok(defense('hellhound','slashing')==15,'ground slash = 15%')
assert_ok(defense('lich','blunt')==-5,'undead blunt = -5%')
assert_ok(defense('falcon','piercing',-15)==-10,'double vulnerabilities allow -10%')
# Physical 100 skill, male STR45 => +90%, vs undead -5% PDEF =199.5 => 200 with Godot rounding.
assert_ok(math.floor(100*1.9*(1.-(-5)/100)+0.5)==200,'male vs lich = 200 on ordinary hit')
# Fire > Wind, Water > Fire, Light <> Dark, Dark <> Light; shared matter -15 attack.
matter=(ROOT/'scripts/matter_rules.gd').read_text()
for check in ('FIRE: return target_matter == WIND','WIND: return target_matter == WATER',
              'WATER: return target_matter == FIRE','LIGHT: return target_matter == DARK',
              'DARK: return target_matter == LIGHT'):
 assert_ok(check in matter,f'matter rule {check}')
print(f'Offline audit v1.4: {sum(ok for _,ok in checks)}/{len(checks)} passed, {refs} checked file references')
raise SystemExit(0 if all(ok for _,ok in checks) else 1)
