#version 450

layout (location = 0) in vec3 Color;
layout (location = 1) in vec2 UV;

layout (location = 0) out vec4 outColor;

layout (binding = 1) uniform sampler2D texture_sampler;

void main() {
	// vec4 color = vec4(Color, 1.0);
	vec4 color = vec4(1.0, 1.0, 1.0, 1.0);
	outColor = texture(texture_sampler, UV) * color;
}
