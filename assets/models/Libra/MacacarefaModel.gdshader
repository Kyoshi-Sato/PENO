shader_type spatial;

//render_mode fog_disabled;

uniform sampler2D texture_albedo;
stencil_mode write, compare_always, 1;
uniform sampler2D color_gradient : source_color; // gradiente 1D (ex: 256x1)

uniform float specular_threshold : hint_range(0.0, 1.0) = 0.5;
uniform float specular_intensity : hint_range(0.0, 4.0) = 1.5;
uniform float outline_width : hint_range(0.0, 10.0, 0.1) = 5.0;

// Número de faixas duras no sombreamento
uniform int steps : hint_range(2, 8) = 3;

void light() {
    vec3 light_dir = normalize(LIGHT);
    vec3 view_dir = normalize(VIEW);

    float light_intensity = max(0.0, dot(light_dir, NORMAL));

    // Discretiza em "steps" (cel shading duro)
    float stepped = floor(light_intensity * float(steps)) / float(steps - 1);

    // Amostra cor no gradiente de acordo com a faixa
    vec3 grad_color = texture(color_gradient, vec2(stepped, 0.5)).rgb;

    // --- Specular Cel Style ---
    vec3 half_dir = normalize(light_dir + view_dir);
    float spec_factor = max(0.0, dot(NORMAL, half_dir));
    spec_factor = step(specular_threshold, spec_factor);

    vec3 specular_color = min(texture(color_gradient, vec2(1.0, 0.5)).rgb * specular_intensity, vec3(1.0));

    grad_color += specular_color * spec_factor;

    grad_color *= ATTENUATION;

    vec3 texture_color = texture(texture_albedo, UV).rgb;

    DIFFUSE_LIGHT += grad_color * texture_color;
}

void fragment() {
    // Para o fresnel, pega a cor "média" do gradiente
    vec3 grad_color = texture(color_gradient, vec2(0.5, 0.5)).rgb;

    ALBEDO = grad_color ;
}
