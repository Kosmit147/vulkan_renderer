#version 450

layout (location = 0) in vec3 Color;
layout (location = 1) in vec2 UV;

layout (location = 0) out vec4 outColor;

layout (binding = 1) uniform sampler2D texture_sampler;

void main() {
	outColor = texture(texture_sampler, UV) * vec4(Color, 1.0);
}
