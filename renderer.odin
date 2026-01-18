package vulkan_renderer

import vk "vendor:vulkan"
import "vendor:glfw"

import "core:log"

when ODIN_DEBUG {
	@(private="file", rodata)
	vk_validation_layers := [?]cstring{
		"VK_LAYER_KHRONOS_validation",
	}
} else {
	@(private="file", rodata)
	vk_validation_layers := [?]cstring{}
}

Renderer :: struct {
	instance: vk.Instance,
}

init_renderer :: proc(renderer: ^Renderer, application_name: cstring) -> (ok := false) {
	vk.load_proc_addresses_global(rawptr(glfw.GetInstanceProcAddress))
	assert(vk.CreateInstance != nil, "Vulkan function pointers not loaded")

	application_info := vk.ApplicationInfo {
		sType = .APPLICATION_INFO,
		pApplicationName = application_name,
		applicationVersion = vk.MAKE_VERSION(1, 0, 0),
		pEngineName = "No Engine",
		engineVersion = vk.MAKE_VERSION(1, 0, 0),
		apiVersion = vk.API_VERSION_1_0,
	}

	glfw_required_extensions := glfw.GetRequiredInstanceExtensions()

	instance_create_info := vk.InstanceCreateInfo {
		sType = .INSTANCE_CREATE_INFO,
		pApplicationInfo = &application_info,
		enabledLayerCount = cast(u32)len(vk_validation_layers),
		ppEnabledLayerNames = raw_data(&vk_validation_layers),
		enabledExtensionCount = cast(u32)len(glfw_required_extensions),
		ppEnabledExtensionNames = raw_data(glfw_required_extensions),
	}

	if vk.CreateInstance(&instance_create_info, nil, &renderer.instance) != .SUCCESS do return
	defer if !ok do vk.DestroyInstance(renderer.instance, nil)

	vk.load_proc_addresses_instance(renderer.instance)

	{
		extension_count: u32
		vk.EnumerateInstanceExtensionProperties(nil, &extension_count, nil)
		extensions := make([dynamic]vk.ExtensionProperties, extension_count)
		defer delete(extensions)
		vk.EnumerateInstanceExtensionProperties(nil, &extension_count, raw_data(extensions))

		log.infof("Supported extensions:")
		for &extension in extensions do log.infof("\t%v", cast(cstring)raw_data(&extension.extensionName))
		log.info()
	}

	{
		layer_count: u32
		vk.EnumerateInstanceLayerProperties(&layer_count, nil)
		layers := make([dynamic]vk.LayerProperties, layer_count)
		defer delete(layers)
		vk.EnumerateInstanceLayerProperties(&layer_count, raw_data(layers))

		log.infof("Supported layers:")
		for &layer in layers do log.infof("\t%v", cast(cstring)raw_data(&layer.layerName))
		log.info()
	}

	ok = true
	return
}

deinit_renderer :: proc(renderer: ^Renderer) {
	vk.DestroyInstance(renderer.instance, nil)
}
