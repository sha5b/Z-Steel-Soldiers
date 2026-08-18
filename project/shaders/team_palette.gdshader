shader_type canvas_item;
// Team palette swap for the Z master art set (see scripts/core/teams.gd).
// The lut texture holds every team's 16-shade paint ramp; row 0 is the
// master (red) ramp baked into the shipped sprites. A fragment EXACTLY
// equal (within float tolerance) to a master shade is replaced by the
// same shade index of the target team's row; every other pixel — neutral
// metal, outlines, faces, fire, muzzle flashes — passes through. The
// original palettes are exact, so only where the original game painted
// team colour gets recoloured (verified pixel-identical against the
// shipped per-team sprites by the --tint self-test).
uniform sampler2D lut;
uniform int team_row = 2;

const float MATCH_EPS = 2.0 / 255.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	for (int i = 0; i < 16; i++) {
		vec3 master = texelFetch(lut, ivec2(i, 0), 0).rgb;
		if (all(lessThanEqual(abs(tex.rgb - master), vec3(MATCH_EPS)))) {
			tex.rgb = texelFetch(lut, ivec2(i, team_row), 0).rgb;
			break;
		}
	}
	COLOR = tex * COLOR;
}
