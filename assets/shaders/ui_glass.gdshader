shader_type canvas_item;
// Vidro fosco para painéis de UI.
//
// Desfoca o que está ATRÁS do painel (a boneca 3D) e tinge com a cor da
// StyleBox. Os cantos arredondados e a sombra vêm da própria StyleBox — é
// geometria de verdade, então o shader não precisa recortar nada.
//
// IMPORTANTE: a StyleBox deste painel deve ter `bg_color` com alpha 1.0.
// Assim `COLOR.a` carrega só o antialiasing da borda arredondada, e quem
// controla a transparência do vidro é `tingimento`, aqui. Se a StyleBox
// vier com alpha < 1, as bordas ficam serrilhadas.
//
// Custo: ler a tela força uma cópia do backbuffer. Use UM painel de vidro
// grande por tela, não vários pequenos — no renderer mobile cada painel
// desses é uma cópia a mais por quadro.

uniform sampler2D tela : hint_screen_texture, filter_linear_mipmap;

/// Nível de mipmap amostrado. Cada +1 dobra o raio do borrão.
uniform float desfoque : hint_range(0.0, 5.0) = 4.5;
/// 0 = totalmente transparente (só o borrão), 1 = cor sólida da StyleBox.
uniform float tingimento : hint_range(0.0, 1.0) = 0.72;
/// Clareia o vidro de leve, para o texto escuro ter contraste garantido.
uniform float brilho : hint_range(-0.2, 0.4) = 0.05;
/// Dessatura o fundo borrado — sem isso o azul da roupa vaza forte no painel.
uniform float dessaturacao : hint_range(0.0, 1.0) = 0.6;
/// Altura (0-1 do painel) em que o vidro "nasce" a partir do topo. Com 0 o
/// painel tem aresta seca e corta o que está atrás — foi o que fez a boneca
/// parecer decepada no ombro. Com ~0.2 ela se dissolve na geada.
uniform float fade_topo : hint_range(0.0, 0.6) = 0.0;

void fragment() {
	vec3 atras = textureLod(tela, SCREEN_UV, desfoque).rgb;

	float cinza = dot(atras, vec3(0.299, 0.587, 0.114));
	atras = mix(atras, vec3(cinza), dessaturacao);

	// Perto do topo o vidro entra aos poucos: `mistura` gradua tanto o
	// tingimento quanto o alpha, então o que está atrás aparece nítido em
	// cima e vai congelando para baixo.
	float mistura = smoothstep(0.0, max(fade_topo, 0.0001), UV.y);
	vec3 vidro = mix(atras, COLOR.rgb, tingimento * mistura) + brilho * mistura;
	COLOR = vec4(clamp(vidro, vec3(0.0), vec3(1.0)), COLOR.a * mistura);
}
