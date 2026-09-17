// Núcleo do shader toon (estilo MToon), compartilhado pelas 5 variantes de
// culling/alpha em assets/shaders/toon_*.gdshader.
//
// COMO AJUSTAR O VISUAL: mude os valores padrão AQUI. As materiais de
// Libra.tscn só definem albedo_tex / albedo_color / alpha_cut, então todo o
// resto vem destes defaults e vale para a personagem inteira de uma vez.
//   shade_tint      -> cor do lado sombreado (mais claro = mais próximo do unshaded)
//   shade_softness  -> 0.02 banda dura estilo anime | 0.18 degradê suave
//   rim_strength    -> brilho de contorno que separa a silhueta do fundo
//
// O material NÃO usa light_energy, só o matiz da luz: "totalmente iluminado"
// é idêntico ao unshaded, independente da energia da DirectionalLight3D.
//
// Obs.: funções de usuário em shader do Godot não enxergam built-ins
// (UV/NORMAL/VIEW/...), por isso tudo entra por parâmetro.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// --- sombra em banda ---
// shade_tint multiplica o albedo no lado escuro. Nunca preto puro: é justamente
// o preto que faz o per-pixel padrão parecer produto inacabado.
uniform vec4 shade_tint : source_color = vec4(0.66, 0.63, 0.78, 1.0);
uniform float shade_shift : hint_range(-1.0, 1.0) = 0.05;
uniform float shade_softness : hint_range(0.001, 0.6) = 0.07;
uniform float light_boost : hint_range(0.0, 3.0) = 1.0;

// --- rim light: separa a silhueta do fundo (essencial no viewport transparente) ---
uniform vec4 rim_color : source_color = vec4(1.0, 0.97, 0.92, 1.0);
uniform float rim_strength : hint_range(0.0, 2.0) = 0.28;
uniform float rim_power : hint_range(0.5, 12.0) = 3.5;

// --- piso de ambiente, para funcionar mesmo sem WorldEnvironment na cena ---
// Só entra em cena se NÃO houver nenhuma luz. Com uma DirectionalLight3D,
// deixe em 0: o piso de luminosidade já vem de shade_tint.
uniform vec4 ambient_color : source_color = vec4(0.42, 0.45, 0.58, 1.0);
uniform float ambient_strength : hint_range(0.0, 2.0) = 0.0;

uniform float alpha_cut : hint_range(0.0, 1.0) = 0.5;

vec3 toon_rim(vec3 n, vec3 v) {
	float fres = 1.0 - clamp(dot(normalize(n), normalize(v)), 0.0, 1.0);
	return rim_color.rgb * pow(fres, rim_power) * rim_strength;
}

vec3 toon_ambient(vec3 albedo) {
	return albedo * ambient_color.rgb * ambient_strength;
}

vec3 toon_diffuse(vec3 albedo, vec3 n, vec3 l, vec3 light_col, float att) {
	float ndl = dot(normalize(n), normalize(l));
	float lit = smoothstep(shade_shift - shade_softness, shade_shift + shade_softness, ndl) * att;
	vec3 tint = mix(shade_tint.rgb, vec3(1.0), lit);
	// Usa só o MATIZ da luz, não a intensidade: assim o material não depende de
	// light_energy e "totalmente iluminado" fica idêntico ao unshaded. É o que
	// mantém o chapado previsível entre cenas com energias diferentes.
	float peak = max(light_col.r, max(light_col.g, light_col.b));
	vec3 hue = light_col / max(peak, 0.0001);
	return albedo * tint * hue * light_boost;
}
