shader_type canvas_item;

// Matrix-style flipping character effect
uniform float columns = 40.0;
uniform float rows = 30.0;
uniform float speed = 3.0;
uniform vec4 char_color : source_color = vec4(0.0, 1.0, 0.8, 1.0);  // Cyan
uniform vec4 bg_color : source_color = vec4(0.0, 0.0, 0.0, 0.9);

float random(vec2 uv) {
    return fract(sin(dot(uv.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

// Generate procedural character-like patterns
float char_pattern(vec2 uv, float char_id) {
    // Create different patterns based on char_id
    float pattern = 0.0;
    
    // Vertical lines
    if (mod(char_id, 4.0) < 1.0) {
        pattern = step(0.4, fract(uv.x * 3.0));
    }
    // Horizontal lines
    else if (mod(char_id, 4.0) < 2.0) {
        pattern = step(0.4, fract(uv.y * 3.0));
    }
    // Diagonal
    else if (mod(char_id, 4.0) < 3.0) {
        pattern = step(0.5, fract((uv.x + uv.y) * 2.0));
    }
    // Cross pattern
    else {
        float vert = step(0.3, abs(uv.x - 0.5));
        float horiz = step(0.3, abs(uv.y - 0.5));
        pattern = 1.0 - (vert * horiz);
    }
    
    return pattern;
}

void fragment() {
    vec2 grid_count = vec2(columns, rows);
    vec2 ipos = floor(UV * grid_count); 
    vec2 fpos = fract(UV * grid_count); 

    // Create a unique seed for this cell
    float cell_seed = random(ipos);
    
    // Each cell gets slightly different speed and time offset
    float individual_speed = speed * (0.8 + cell_seed * 0.4);
    float time_offset = cell_seed * 1000.0;
    
    // Animated character index
    float char_index = floor(mod((TIME + time_offset) * individual_speed, 16.0));
    
    // Generate character pattern
    float pattern = char_pattern(fpos, char_index);
    
    // Flicker effect - desynchronized per cell
    float flicker_speed = speed * 0.5 * (0.7 + cell_seed * 0.6);
    float flicker = step(0.3, random(ipos + floor(TIME * flicker_speed)));
    
    float mask = pattern * flicker;
    
    vec3 final_rgb = mix(bg_color.rgb, char_color.rgb, mask);
    COLOR = vec4(final_rgb, bg_color.a);
}
