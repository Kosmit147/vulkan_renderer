package vulkan_renderer

import vk "vendor:vulkan"

import "core:slice"

create_shader_module :: proc(device: vk.Device, bytecode: []byte) -> (module: vk.ShaderModule, ok := false) {
	shader_module_create_info := vk.ShaderModuleCreateInfo {
		sType = .SHADER_MODULE_CREATE_INFO,
		codeSize = slice.size(bytecode),
		pCode = cast(^u32)raw_data(bytecode),
	}
	if vk.CreateShaderModule(device, &shader_module_create_info, nil, &module) != .SUCCESS do return
	ok = true
	return
}

destroy_shader_module :: proc(device: vk.Device, module: vk.ShaderModule) {
	vk.DestroyShaderModule(device, module, nil)
}
